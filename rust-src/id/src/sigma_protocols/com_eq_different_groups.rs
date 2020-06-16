//! The module provides the implementation of the `com_eq_diff_groups` sigma
//! protocol. This protocol enables one to prove that the value committed to in
//! two commitments $C_1$ and $C_2$ in (potentially) two different groups (of
//! the same order) is the same.
use curve_arithmetic::Curve;
use ff::Field;
use rand::*;

use crypto_common::*;
use crypto_common_derive::*;
use pedersen_scheme::{Commitment, CommitmentKey, Randomness, Value};
use random_oracle::RandomOracle;

#[derive(Debug)]
pub struct ComEqDiffGrpsSecret<'a, C1: Curve, C2: Curve<Scalar = C1::Scalar>> {
    pub value:      &'a Value<C2>,
    pub rand_cmm_1: &'a Randomness<C1>,
    pub rand_cmm_2: &'a Randomness<C2>,
}

#[derive(Clone, Debug, Eq, PartialEq, Copy, Serialize, SerdeBase16Serialize)]
pub struct ComEqDiffGrpsProof<C1: Curve, C2: Curve<Scalar = C1::Scalar>> {
    challenge: C1::Scalar,
    witness:   (C1::Scalar, C1::Scalar, C2::Scalar),
}

/// Construct a proof of knowledge from public and secret values.
/// The input parameters are as follows.
/// * `ro` - Random oracle used in the challenge computation. This can be used
///   to make sure that the proof is only valid in a certain context.
/// * `commitment_{1,2}` - A pair of commitments to the same value in different
///   groups.
/// * `cmm_key_{1,2}` - A pair of commitment keys (for the first and second
///   commitment, respectively).
/// * `secret` - The triple $(a_1, a_2, r)$ of the value $a_1$ that is commited,
///   and the randomnesses $a_2$ and $r$ for the first and second commitment,
///   respectively.
/// * `csprng` - A cryptographically secure random number generator.
#[allow(non_snake_case)]
pub fn prove_com_eq_diff_grps<C1: Curve, C2: Curve<Scalar = C1::Scalar>, R: Rng>(
    ro: RandomOracle,
    commitment_1: &Commitment<C1>,
    commitment_2: &Commitment<C2>,
    cmm_key_1: &CommitmentKey<C1>,
    cmm_key_2: &CommitmentKey<C2>,
    secret: &ComEqDiffGrpsSecret<C1, C2>,
    csprng: &mut R,
) -> ComEqDiffGrpsProof<C1, C2> {
    let y = commitment_1;
    let cC = commitment_2;

    let hasher = ro
        .append_bytes("com_eq_different_groups")
        .append(y)
        .append(cC)
        .append(cmm_key_1)
        .append(cmm_key_2);

    let alpha_1 = Value::generate_non_zero(csprng);
    let (u, alpha_2) = cmm_key_1.commit(&alpha_1, csprng);
    let (v, cR) = cmm_key_2.commit(alpha_1.view(), csprng);

    let challenge = hasher.append(&u).finish_to_scalar::<C1, _>(&v);
    // if the computed challenge is 0 the proof will not be valid (unless extremely
    // exceptional circumstances happen). Thus in such a case we resample.
    let mut s_1 = challenge;
    s_1.mul_assign(secret.value);
    s_1.negate();
    s_1.add_assign(&alpha_1);

    let mut s_2 = challenge;
    s_2.mul_assign(secret.rand_cmm_1);
    s_2.negate();
    s_2.add_assign(&alpha_2);

    let mut t = challenge;
    t.mul_assign(secret.rand_cmm_2);
    t.negate();
    t.add_assign(&cR);
    ComEqDiffGrpsProof {
        challenge,
        witness: (s_1, s_2, t),
    }
}

/// Verify a proof of knowledge from public and secret values.
/// The input parameters are as follows.
/// * `ro` - Random oracle used in the challenge computation. This can be used
///   to make sure that the proof is only valid in a certain context.
/// * `commitment_{1,2}` - A pair of commitments to the same value in different
///   groups.
/// * `cmm_key_{1,2}` - A pair of commitment keys (for the first and second
///   commitment respectively).
#[allow(non_snake_case)]
#[allow(clippy::many_single_char_names)]
pub fn verify_com_eq_diff_grps<C1: Curve, C2: Curve<Scalar = C1::Scalar>>(
    ro: RandomOracle,
    commitment_1: &Commitment<C1>,
    commitment_2: &Commitment<C2>,
    cmm_key_1: &CommitmentKey<C1>,
    cmm_key_2: &CommitmentKey<C2>,
    proof: &ComEqDiffGrpsProof<C1, C2>,
) -> bool {
    let y = commitment_1;
    let cC = commitment_2;

    let CommitmentKey(cG1, cG2) = cmm_key_1;
    let CommitmentKey(g, h) = cmm_key_2;

    let (s_1, s_2, t) = proof.witness;

    let u = y
        .mul_by_scalar(&proof.challenge)
        .plus_point(&cG1.mul_by_scalar(&s_1))
        .plus_point(&cG2.mul_by_scalar(&s_2));
    let v = cC
        .mul_by_scalar(&proof.challenge)
        .plus_point(&g.mul_by_scalar(&s_1))
        .plus_point(&h.mul_by_scalar(&t));

    let computed_challenge = ro
        .append_bytes("com_eq_different_groups")
        .append(y)
        .append(cC)
        .append(cmm_key_1)
        .append(cmm_key_2)
        .append(&u)
        .finish_to_scalar::<C1, _>(&v);
    computed_challenge == proof.challenge
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sigma_protocols::common::*;
    use pairing::bls12_381::{G1Affine, G2Affine};
    use rand::rngs::ThreadRng;

    #[test]
    pub fn test_com_eq_diff_grps_correctness() {
        let mut csprng = thread_rng();
        for _i in 0..100 {
            let a_1 = Value::<G2Affine>::generate_non_zero(&mut csprng);
            let cmm_key_1 = CommitmentKey::<G1Affine>::generate(&mut csprng);
            let cmm_key_2 = CommitmentKey::<G2Affine>::generate(&mut csprng);

            let (u, a_2) = cmm_key_1.commit((&a_1).view(), &mut csprng);
            let (v, r) = cmm_key_2.commit(&a_1, &mut csprng);

            let challenge_prefix = generate_challenge_prefix(&mut csprng);
            let ro = RandomOracle::domain(&challenge_prefix);

            let secret = ComEqDiffGrpsSecret {
                value:      &a_1,
                rand_cmm_1: &a_2,
                rand_cmm_2: &r,
            };
            let proof = prove_com_eq_diff_grps::<G1Affine, G2Affine, ThreadRng>(
                ro.split(),
                &u,
                &v,
                &cmm_key_1,
                &cmm_key_2,
                &secret,
                &mut csprng,
            );
            assert!(verify_com_eq_diff_grps(
                ro.split(),
                &u,
                &v,
                &cmm_key_1,
                &cmm_key_2,
                &proof
            ));
        }
    }

    #[test]
    pub fn test_com_eq_diff_grps_soundness() {
        let mut csprng = thread_rng();
        for _i in 0..100 {
            // Generate proof
            let a_1 = Value::<G2Affine>::generate_non_zero(&mut csprng);
            let cmm_key_1 = CommitmentKey::<G1Affine>::generate(&mut csprng);
            let cmm_key_2 = CommitmentKey::<G2Affine>::generate(&mut csprng);

            let (u, a_2) = cmm_key_1.commit((&a_1).view(), &mut csprng);
            let (v, r) = cmm_key_2.commit(&a_1, &mut csprng);

            let challenge_prefix = generate_challenge_prefix(&mut csprng);
            let ro = RandomOracle::domain(&challenge_prefix);

            let secret = ComEqDiffGrpsSecret {
                value:      &a_1,
                rand_cmm_1: &a_2,
                rand_cmm_2: &r,
            };
            let proof = prove_com_eq_diff_grps::<G1Affine, G2Affine, ThreadRng>(
                ro.split(),
                &u,
                &v,
                &cmm_key_1,
                &cmm_key_2,
                &secret,
                &mut csprng,
            );

            // Construct invalid parameters
            let wrong_ro = RandomOracle::domain(generate_challenge_prefix(&mut csprng));
            let wrong_cmm_key_1 = CommitmentKey::<G1Affine>::generate(&mut csprng);
            let wrong_cmm_key_2 = CommitmentKey::<G2Affine>::generate(&mut csprng);
            let (wrong_u, _) = wrong_cmm_key_1.commit((&a_1).view(), &mut csprng);
            let (wrong_v, _) = wrong_cmm_key_2.commit(&a_1, &mut csprng);

            // Verify failure for invalid parameters
            assert!(verify_com_eq_diff_grps(
                ro.split(),
                &u,
                &v,
                &cmm_key_1,
                &cmm_key_2,
                &proof
            ));
            assert!(!verify_com_eq_diff_grps(
                wrong_ro, &u, &v, &cmm_key_1, &cmm_key_2, &proof
            ));
            assert!(!verify_com_eq_diff_grps(
                ro.split(),
                &wrong_u,
                &v,
                &cmm_key_1,
                &cmm_key_2,
                &proof
            ));
            assert!(!verify_com_eq_diff_grps(
                ro.split(),
                &u,
                &wrong_v,
                &cmm_key_1,
                &cmm_key_2,
                &proof
            ));
            assert!(!verify_com_eq_diff_grps(
                ro.split(),
                &u,
                &v,
                &wrong_cmm_key_1,
                &cmm_key_2,
                &proof
            ));
            assert!(!verify_com_eq_diff_grps(
                ro.split(),
                &u,
                &v,
                &cmm_key_1,
                &wrong_cmm_key_2,
                &proof
            ));
        }
    }

    #[test]
    pub fn test_com_eq_diff_grps_proof_serialization() {
        let mut csprng = thread_rng();
        for _i in 0..100 {
            let challenge = G1Affine::generate_scalar(&mut csprng);
            let witness = (
                G1Affine::generate_scalar(&mut csprng),
                G1Affine::generate_scalar(&mut csprng),
                G1Affine::generate_scalar(&mut csprng),
            );
            let ap = ComEqDiffGrpsProof::<G1Affine, G2Affine> { challenge, witness };
            let app = serialize_deserialize(&ap);
            assert!(app.is_ok());
            assert_eq!(ap, app.unwrap());
        }
    }
}
