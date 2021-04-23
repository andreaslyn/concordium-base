//! Some command line auxiliary utilities.
//! At the moment we have encryption and decryption in the formats used by other
//! parts of the Concordium project.

use clap::AppSettings;
use client_server_helpers::*;
use failure::ResultExt;
use std::path::PathBuf;
use structopt::StructOpt;

#[derive(StructOpt)]
struct ConfigEncrypt {
    #[structopt(long = "in", help = "File to encrypt.")]
    input: PathBuf,
    #[structopt(long = "out", help = "Name of the output file.")]
    output: PathBuf,
}

#[derive(StructOpt)]
struct ConfigDecrypt {
    #[structopt(long = "in", help = "File to decrypt.")]
    input: PathBuf,
    #[structopt(
        long = "out",
        help = "Place to output the decryption. Defaults to standard output."
    )]
    output: Option<PathBuf>,
}

#[derive(StructOpt)]
#[structopt(
    about = "Various helper utilities",
    author = "Concordium",
    version = "0.0"
)]
enum Utils {
    #[structopt(name = "encrypt", about = "Encrypt the contents of the supplied file.")]
    Encrypt(ConfigEncrypt),
    #[structopt(name = "decrypt", about = "Decrypt the contents of the supplied file.")]
    Decrypt(ConfigDecrypt),
}

fn main() -> failure::Fallible<()> {
    let app = Utils::clap()
        .setting(AppSettings::ArgRequiredElseHelp)
        .global_setting(AppSettings::ColoredHelp);
    let matches = app.get_matches();
    let utls = Utils::from_clap(&matches);
    match utls {
        Utils::Encrypt(cfg) => handle_encrypt(cfg),
        Utils::Decrypt(cfg) => handle_decrypt(cfg),
    }
}

fn handle_encrypt(cfg: ConfigEncrypt) -> failure::Fallible<()> {
    let data = std::fs::read(&cfg.input).context("Cannot read input file.")?;
    loop {
        let pass = rpassword::read_password_from_tty(Some("Enter password to encrypt with: "))?;
        let pass2 = rpassword::read_password_from_tty(Some("Re-enter password: "))?;
        if pass != pass2 {
            println!("The passwords were not equal. Try again.");
        } else {
            let encrypted =
                crypto_common::encryption::encrypt(&pass.into(), &data, &mut rand::thread_rng());
            eprintln!("Writing output to {}", cfg.output.to_string_lossy());
            write_json_to_file(&cfg.output, &encrypted)?;
            return Ok(());
        }
    }
}

fn handle_decrypt(cfg: ConfigDecrypt) -> failure::Fallible<()> {
    let data = std::fs::read(&cfg.input).context("Cannot read input file.")?;
    let parsed_data = serde_json::from_slice(&data)?;
    let pass = rpassword::read_password_from_tty(Some("Enter password to decrypt with: "))?;
    let plaintext = match crypto_common::encryption::decrypt(&pass.into(), &parsed_data) {
        Ok(pt) => pt,
        Err(_) => failure::bail!("Could not decrypt."),
    };
    match cfg.output {
        Some(fname) => {
            eprintln!("Writing output to {}", fname.to_string_lossy());
            std::fs::write(fname, &plaintext)?;
        }
        None => {
            let s = String::from_utf8(plaintext)?;
            println!("{}", s);
        }
    }
    Ok(())
}
