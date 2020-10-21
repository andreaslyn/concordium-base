use std::{convert::Infallible, fs, fs::OpenOptions, io::prelude::*, path::PathBuf, sync::Arc};

use crypto_common::{base16_encode_string, Versioned, VERSION_0};
use curve_arithmetic::*;
use id::{
    ffi::AttributeKind,
    identity_provider::{sign_identity_object, validate_request as ip_validate_request},
    types::*,
};
use log::info;
use pairing::bls12_381::{Bls12, G1};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{from_str, to_string};
use structopt::StructOpt;
use url::form_urlencoded::byte_serialize;
use warp::{
    http::{Response, StatusCode},
    hyper::header::{CONTENT_TYPE, LOCATION},
    Filter,
};

type ExampleCurve = G1;
type ExamplePairing = Bls12;
type ExampleAttributeList = AttributeList<<Bls12 as Pairing>::ScalarField, AttributeKind>;

/// 10.0.2.2 is how an Android emulator accesses the host machine, which is what
/// we are using for this proof-of-concept. The callback_location has to
/// point to the location where the wallet can retrieve the identity object
/// when it is available.
const RETRIEVE_URL: &str = "http://10.0.2.2:8100/api/identity/";

const ID_VERIFICATION_URL: &str = "http://localhost:8101/api/verify";

#[derive(Deserialize)]
struct IdentityObjectRequest {
    #[serde(rename = "idObjectRequest")]
    id_object_request: Versioned<PreIdentityObject<ExamplePairing, ExampleCurve>>,
}

/// Holds the query parameters expected by the service.
#[derive(Deserialize)]
struct Input {
    /// The JSON serialized and URL encoded identity request
    /// object.
    /// The name 'state' is what is expected as a GET parameter name.
    #[serde(rename = "state")]
    state: String,
    /// The URI where the response will be returned.
    #[serde(rename = "redirect_uri")]
    redirect_uri: String,
}

/// JSON object that the wallet expects to be returned when polling for an
/// identity object.
#[derive(Serialize)]
struct IdentityTokenContainer {
    status: String,
    token:  String,
    detail: String,
}

/// Holds the information required to create the IdentityObject and forward to
/// the correct response URL that the wallet is expecting. Used for easier
/// passing between methods.
struct ValidatedRequest {
    /// The pre-identity-object contained in the initial request.
    request: PreIdentityObject<ExamplePairing, ExampleCurve>,
    /// The identity provider data needed to sign the request.
    ip_data: Arc<IpData<ExamplePairing>>,
    /// The URI that the ID object should be returned to after we've done the
    /// verification of the user.
    redirect_uri: String,
}

/// Structure used to receive the correct command line arguments by using
/// StructOpt.
#[derive(Debug, StructOpt)]
struct IdentityProviderServiceConfiguration {
    #[structopt(long = "global-context", help = "File with global context.")]
    global_context_file: PathBuf,
    #[structopt(
        long = "identity-provider",
        help = "File with the identity provider as JSON."
    )]
    identity_provider_file: PathBuf,
    #[structopt(
        long = "anonymity-revokers",
        help = "File with the list of anonymity revokers as JSON."
    )]
    anonymity_revokers_file: PathBuf,
    #[structopt(
        long = "port",
        default_value = "8100",
        help = "Port on which the server will listen on."
    )]
    port: u16,
}

#[tokio::main]
async fn main() {
    env_logger::init();
    let app = IdentityProviderServiceConfiguration::clap()
        .setting(clap::AppSettings::ArgRequiredElseHelp)
        .global_setting(clap::AppSettings::ColoredHelp);
    let matches = app.get_matches();
    let opt = IdentityProviderServiceConfiguration::from_clap(&matches);

    info!("Reading the provided IP, AR and global context configurations.");
    let ip_data_contents =
        fs::read_to_string(opt.identity_provider_file).expect("Unable to read ip data file.");
    let ar_info_contents =
        fs::read_to_string(opt.anonymity_revokers_file).expect("Unable to read ar info file.");
    let global_context_contents = fs::read_to_string(opt.global_context_file)
        .expect("Unable to read global context info file.");

    let ip_data: Arc<IpData<ExamplePairing>> = Arc::new(
        from_str(&ip_data_contents).expect("File did not contain a valid IpData object as JSON."),
    );
    let ar_info: Arc<ArInfos<ExampleCurve>> = Arc::new(
        from_str(&ar_info_contents).expect("File did not contain a valid ArInfos object as JSON"),
    );
    let global_context: Arc<GlobalContext<ExampleCurve>> = Arc::new(
        from_str(&global_context_contents)
            .expect("File did not contain a valid GlobalContext object as JSON"),
    );

    // Create the 'database' directories for storing IdentityObjects and
    // AnonymityRevocationRecords.
    fs::create_dir_all("database/revocation").expect("Unable to create revocation directory.");
    fs::create_dir_all("database/identity").expect("Unable to create identity directory");
    info!("Configurations have been loaded successfully.");

    let retrieve_identity = warp::get()
        .and(warp::path!("api" / "identity" / String))
        .map(|id_cred_pub| {
            info!("Queried for receiving identity: {}", id_cred_pub);
            match fs::read_to_string(std::path::Path::new("database/identity").join(id_cred_pub)) {
                Ok(identity_object) => {
                    info!("Identity object found");

                    let wrapped_identity_object =
                        "{ \"identityObject\": ".to_string() + &identity_object + "}";
                    let urlencoded_identity_object: String =
                        byte_serialize(wrapped_identity_object.as_bytes()).collect();

                    let identity_token_container = IdentityTokenContainer {
                        status: "done".to_string(),
                        token:  urlencoded_identity_object,
                        detail: "".to_string(),
                    };

                    Response::builder()
                        .header(CONTENT_TYPE, "application/json")
                        .body(to_string(&identity_token_container).unwrap())
                }
                Err(_e) => {
                    info!("Identity object does not exist");
                    let error_identity_token_container = IdentityTokenContainer {
                        status: "error".to_string(),
                        detail: "Identity object does not exist".to_string(),
                        token:  "".to_string(),
                    };
                    Response::builder()
                        .header(CONTENT_TYPE, "application/json")
                        .body(to_string(&error_identity_token_container).unwrap())
                }
            }
        });

    let create_identity = warp::get()
        .and(warp::path!("api" / "identity"))
        .and(warp::query().map(move |input: Input| {
            info!("Queried for creating an identity");
            extract_and_validate_request(
                Arc::clone(&ip_data),
                Arc::clone(&ar_info),
                Arc::clone(&global_context),
                input,
            )
        }))
        .and_then(create_signed_identity_object);

    info!("Booting up HTTP server. Listening on port 8100.");
    warp::serve(create_identity.or(retrieve_identity))
        .run(([0, 0, 0, 0], opt.port))
        .await;
}

/// Asks the identity verifier to verify the person and return the associated
/// attribute list. The attribute list is used to create the identity object
/// that is then signed and saved. If successful a re-direct to the URL where
/// the identity object is available is returned.
async fn create_signed_identity_object(
    identity_object_input: Result<ValidatedRequest, String>,
) -> Result<impl warp::Reply, Infallible> {
    let identity_object_input = match identity_object_input {
        Ok(request) => request,
        Err(e) => {
            return Ok(Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .body(format!("Failed validation of the request due to: {}", e)))
        }
    };
    let request = identity_object_input.request;

    // Identity verification process between the identity provider and the identity
    // verifier. In this example the identity verifier is queried and will
    // always just return a static attribute list without doing any actual
    // verification of an identity.
    let client = Client::new();
    let attribute_list = match client.post(ID_VERIFICATION_URL).send().await {
        Ok(attribute_list) => match attribute_list.json().await {
            Ok(attribute_list) => attribute_list,
            Err(e) => {
                return Ok(Response::builder()
                    .status(StatusCode::BAD_REQUEST)
                    .body(format!(
                        "Unable to deserialize attribute list received from identity verifier: {}",
                        e
                    )))
            }
        },
        Err(e) => {
            return Ok(Response::builder()
                .status(StatusCode::SERVICE_UNAVAILABLE)
                .body(format!(
                    "The identity verifier service is unavailable. Try again later: {}",
                    e
                )))
        }
    };

    // At this point the identity has been verified, and the identity provider
    // constructs the identity object and signs it. An anonymity revocation
    // record and the identity object are persisted, so that they can be
    // retrieved when needed. The constructed response contains a redirect to a
    // webservice that returns the identity object constructed here.

    // This is hardcoded for the proof-of-concept.
    let now = YearMonth::now();
    let valid_to_next_year = YearMonth {
        year:  now.year + 1,
        month: now.month,
    };

    let alist = ExampleAttributeList {
        valid_to:     valid_to_next_year,
        created_at:   now,
        alist:        attribute_list,
        max_accounts: 200,
        _phantom:     Default::default(),
    };

    let signature = match sign_identity_object(
        &request,
        &identity_object_input.ip_data.public_ip_info,
        &alist,
        &identity_object_input.ip_data.ip_secret_key,
    ) {
        Ok(signature) => signature,
        Err(e) => {
            return Ok(Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(format!(
                    "It was not possible to sign the identity object: {}",
                    e
                )))
        }
    };

    let base16_encoded_id_cred_pub = base16_encode_string(&request.id_cred_pub);

    match save_revocation_record(&request, base16_encoded_id_cred_pub.clone()) {
        Ok(_saved) => (),
        Err(e) => {
            return Ok(Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(e))
        }
    };

    let id = IdentityObject {
        pre_identity_object: request,
        alist,
        signature,
    };

    let versioned_id = Versioned::new(VERSION_0, id);
    let serialized_versioned_id = to_string(&versioned_id).unwrap();

    // Store a record containing the created IdentityObject.
    match store_record(
        &serialized_versioned_id,
        base16_encoded_id_cred_pub.clone(),
        "identity".to_string(),
    ) {
        Ok(_saved) => (),
        Err(e) => {
            return Ok(Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(e))
        }
    };

    // 10.0.2.2 is how an Android emulator accesses the host machine, which is what
    // we are using for this proof-of-concept. The callback_location has to
    // point to the location where the wallet can retrieve the identity object
    // when it is available.
    let callback_location = identity_object_input.redirect_uri.clone()
        + "#code_uri="
        + RETRIEVE_URL
        + &base16_encoded_id_cred_pub;

    info!("Identity was successfully created. Returning URI where it can be retrieved.");

    Ok(Response::builder()
        .header(LOCATION, callback_location)
        .status(StatusCode::FOUND)
        .body("".to_string()))
}

/// Validate that the received request is well-formed.
/// This check that all the cryptographic values are valid, and that the zero
/// knowledge proofs in the request are valid.
///
/// The return value is either
///
/// - Ok(ValidatedRequest) if the request is valid or
/// - Err(msg) where `msg` is a string describing the error.
fn extract_and_validate_request(
    ip_data: Arc<IpData<ExamplePairing>>,
    ar_info: Arc<ArInfos<ExampleCurve>>,
    global_context: Arc<GlobalContext<ExampleCurve>>,
    input: Input,
) -> Result<ValidatedRequest, String> {
    let request: IdentityObjectRequest =
        from_str(&input.state).map_err(|e| format!("Could not parse identity object {}", e))?;
    if request.id_object_request.version != VERSION_0 {
        return Err(format!(
            "Unsupported version {}",
            request.id_object_request.version
        ));
    }
    let request = request.id_object_request.value;

    let context = IPContext {
        ip_info:        &ip_data.public_ip_info,
        ars_infos:      &ar_info.anonymity_revokers,
        global_context: &global_context,
    };

    match ip_validate_request(&request, context) {
        Ok(()) => Ok(ValidatedRequest {
            request,
            ip_data,
            redirect_uri: input.redirect_uri,
        }),
        Err(e) => Err(format!(
            "The request could not be validated by the identity provider: {}",
            e
        )),
    }
}

/// Creates and saves the revocation record to the file system (which should be
/// a database, but for the proof-of-concept we use the file system).
fn save_revocation_record(
    pre_identity_object: &PreIdentityObject<ExamplePairing, ExampleCurve>,
    base16_id_cred_pub: String,
) -> std::result::Result<(), String> {
    let ar_record = AnonymityRevocationRecord {
        id_cred_pub: pre_identity_object.id_cred_pub,
        ar_data:     pre_identity_object.ip_ar_data.clone(),
    };

    let serialized_ar_record = to_string(&ar_record).unwrap();
    store_record(
        &serialized_ar_record,
        base16_id_cred_pub,
        "revocation".to_string(),
    )
}

/// Writes record to the provided subdirectory under 'database/'. The filename
/// is set to id_cred_pub, which is expected to be the base16 serialized
/// id_cred_pub.
fn store_record(
    record: &str,
    id_cred_pub: String,
    directory: String,
) -> std::result::Result<(), String> {
    let mut file = match OpenOptions::new()
        .write(true)
        .create(true)
        .open(format!("database/{}/{}", directory, id_cred_pub))
    {
        Ok(file) => file,
        Err(e) => return Err(format!("Failed accessing {} file: {}", directory, e)),
    };

    match writeln!(file, "{}", record) {
        Ok(_result) => Ok(()),
        Err(e) => Err(format!("Failed writing {} to file: {}", directory, e)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_successful_validation_and_response() {
        // Given
        let request = include_str!("../data/valid_request.json");
        let ip_data_contents = include_str!("../data/identity_provider.json");
        let ar_info_contents = include_str!("../data/anonymity_revokers.json");
        let global_context_contents = include_str!("../data/global.json");

        let ip_data: Arc<IpData<ExamplePairing>> = Arc::new(
            from_str(&ip_data_contents)
                .expect("File did not contain a valid IpData object as JSON."),
        );
        let ar_info: Arc<ArInfos<ExampleCurve>> = Arc::new(
            from_str(&ar_info_contents)
                .expect("File did not contain a valid ArInfos object as JSON"),
        );
        let global_context: Arc<GlobalContext<ExampleCurve>> = Arc::new(
            from_str(&global_context_contents)
                .expect("File did not contain a valid GlobalContext object as JSON"),
        );

        let input = Input {
            state:        request.to_string(),
            redirect_uri: "test".to_string(),
        };

        // When
        let response = extract_and_validate_request(
            Arc::clone(&ip_data),
            Arc::clone(&ar_info),
            Arc::clone(&global_context),
            input,
        );

        // Then
        assert!(response.is_ok());
    }

    #[test]
    fn test_verify_failed_validation() {
        // Given
        let request = include_str!("../data/fail_validation_request.json");
        let ip_data_contents = include_str!("../data/identity_provider.json");
        let ar_info_contents = include_str!("../data/anonymity_revokers.json");
        let global_context_contents = include_str!("../data/global.json");

        let ip_data: Arc<IpData<ExamplePairing>> = Arc::new(
            from_str(&ip_data_contents)
                .expect("File did not contain a valid IpData object as JSON."),
        );
        let ar_info: Arc<ArInfos<ExampleCurve>> = Arc::new(
            from_str(&ar_info_contents)
                .expect("File did not contain a valid ArInfos object as JSON"),
        );
        let global_context: Arc<GlobalContext<ExampleCurve>> = Arc::new(
            from_str(&global_context_contents)
                .expect("File did not contain a valid GlobalContext object as JSON"),
        );

        let input = Input {
            state:        request.to_string(),
            redirect_uri: "test".to_string(),
        };

        // When
        let response = extract_and_validate_request(
            Arc::clone(&ip_data),
            Arc::clone(&ar_info),
            Arc::clone(&global_context),
            input,
        );

        // Then (the zero knowledge proofs could not be verified, so we fail)
        assert!(response.is_err());
    }
}