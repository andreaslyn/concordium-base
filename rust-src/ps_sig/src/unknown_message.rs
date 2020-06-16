use crypto_common::*;
use curve_arithmetic::*;
use pedersen_scheme::Commitment;

use rand::*;
use std::ops::Deref;

#[derive(Debug, Serialize)]
pub struct UnknownMessage<C: Pairing>(pub C::G1);

impl<C: Pairing> PartialEq for UnknownMessage<C> {
    fn eq(&self, other: &Self) -> bool { self.0 == other.0 }
}

impl<C: Pairing> Eq for UnknownMessage<C> {}

/// This trait allows automatic conversion of &Value<C> to &C::Scalar.
impl<P: Pairing> Deref for UnknownMessage<P> {
    type Target = P::G1;

    fn deref(&self) -> &P::G1 { &self.0 }
}

impl<P: Pairing> From<Commitment<P::G1>> for UnknownMessage<P> {
    fn from(cmm: Commitment<P::G1>) -> Self { UnknownMessage(cmm.0) }
}

/// Randomness used to retrieve signature on the message from signature on an
/// unknown message.
#[derive(Debug, Serialize)]
#[repr(transparent)]
pub struct SigRetrievalRandomness<P: Pairing> {
    pub randomness: P::ScalarField,
}

impl<P: Pairing> Deref for SigRetrievalRandomness<P> {
    type Target = P::ScalarField;

    fn deref(&self) -> &P::ScalarField { &self.randomness }
}

impl<C: Pairing> UnknownMessage<C> {
    /// Generate a valid, but arbitrary message. Exposed because it can be used
    /// for testing protocols built on top of the signature scheme.
    pub fn arbitrary<T: Rng>(csprng: &mut T) -> UnknownMessage<C> {
        UnknownMessage(C::G1::generate(csprng))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pairing::bls12_381::Bls12;

    macro_rules! macro_test_unknown_message_to_byte_conversion {
        ($function_name:ident, $pairing_type:path) => {
            #[test]
            pub fn $function_name() {
                let mut csprng = thread_rng();
                for _i in 0..20 {
                    let x = UnknownMessage::<$pairing_type>::arbitrary(&mut csprng);
                    let y = serialize_deserialize(&x);
                    assert!(y.is_ok());
                    assert_eq!(x, y.unwrap());
                }
            }
        };
    }
    macro_test_unknown_message_to_byte_conversion!(
        unknown_message_to_byte_conversion_bls12_381,
        Bls12
    );
}
