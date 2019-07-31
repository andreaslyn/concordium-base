#[macro_use]
extern crate criterion;
extern crate rand;

extern crate aggregate_sig;
use aggregate_sig::aggregate_sig::*;

use criterion::Criterion;
use pairing::bls12_381::Bls12;
use rand::{thread_rng, Rng};

macro_rules! rand_m_of_length {
    ($length:expr, $rng:expr) => {{
        let mut m: Vec<u8> = Vec::with_capacity($length);
        for _ in 0..$length {
            m.push($rng.gen::<u8>());
        }
        m
    }};
}

macro_rules! get_sks_pks {
    ($n:expr, $rng:expr) => {{
        let sks: Vec<SecretKey<Bls12>> = (0..$n)
            .map(|_| SecretKey::<Bls12>::generate(&mut $rng))
            .collect();

        let pks: Vec<PublicKey<Bls12>> = sks
            .iter()
            .map(|x| PublicKey::<Bls12>::from_secret(x))
            .collect();

        (sks, pks)
    };};
}

fn bench_sign_and_verify(c: &mut Criterion) {
    let mut csprng = thread_rng();
    let m = rand_m_of_length!(1000, csprng);
    let m_clone = m.clone();

    let sk = SecretKey::<Bls12>::generate(&mut csprng);
    let pk = PublicKey::<Bls12>::from_secret(&sk);
    let sig = sign_message(&sk, m.as_slice());
    c.bench_function("sign", move |b| b.iter(|| sign_message(&sk, m.as_slice())));
    c.bench_function("verify", move |b| {
        b.iter(|| verify(m_clone.as_slice(), &pk, &sig))
    });
}

fn bench_aggregate_sig(c: &mut Criterion) {
    let mut csprng = thread_rng();

    let sk1 = SecretKey::<Bls12>::generate(&mut csprng);
    let sk2 = SecretKey::<Bls12>::generate(&mut csprng);

    let m1 = rand_m_of_length!(1000, csprng);
    let m2 = rand_m_of_length!(1000, csprng);
    let sig1 = sign_message(&sk1, &m1);
    let sig2 = sign_message(&sk2, &m2);
    // TODO, make code below work

    c.bench_function("aggregate_signature", move |b| {
        b.iter(|| aggregate_sig(sig1.clone(), sig2.clone()))
    });
}

macro_rules! n_rand_ms_of_length {
    ($n:expr, $length:expr, $rng:expr) => {{
        let mut ms: Vec<_> = Vec::with_capacity($n);
        for _ in 0..$n {
            let m = rand_m_of_length!($length, $rng);
            ms.push(m);
        }
        ms
    }};
}

fn bench_verify_aggregate_sig(c: &mut Criterion) {
    let mut csprng = thread_rng();
    let n = 200;
    let (sks, pks) = get_sks_pks!(n, csprng);
    let ms: Vec<_> = n_rand_ms_of_length!(n, 1000, csprng);

    let mut agg_sig = sign_message(&sks[0], &ms[0]);
    for i in 1..n {
        let new_sig = sign_message(&sks[i], &ms[i]);
        agg_sig = aggregate_sig(new_sig, agg_sig);
    }

    let ms_clone = ms.clone();
    let pks_clone = pks.clone();
    let agg_sig_clone = agg_sig.clone();

    c.bench_function("verify_aggregate_v1", move |b| {
        let mut m_pk_pairs: Vec<(&[u8], PublicKey<Bls12>)> = Vec::with_capacity(n);
        for i in 0..n {
            let m_pk = (ms_clone[i].as_slice(), pks_clone[i].clone());
            m_pk_pairs.push(m_pk);
        }
        b.iter(|| verify_aggregate_sig_v1(&m_pk_pairs.clone(), agg_sig_clone.clone()))
    });

    let ms_clone = ms.clone();
    let pks_clone = pks.clone();
    let agg_sig_clone = agg_sig.clone();
    c.bench_function("verify_aggregate_v2", move |b| {
        let mut m_pk_pairs: Vec<(&[u8], PublicKey<Bls12>)> = Vec::with_capacity(n);
        for i in 0..n {
            let m_pk = (ms_clone[i].as_slice(), pks_clone[i].clone());
            m_pk_pairs.push(m_pk);
        }
        b.iter(|| verify_aggregate_sig_v2(&m_pk_pairs.clone(), agg_sig_clone.clone()))
    });

    let ms_clone = ms.clone();
    let pks_clone = pks.clone();
    let agg_sig_clone = agg_sig.clone();
    c.bench_function("verify_aggregate_v3", move |b| {
        let mut m_pk_pairs: Vec<(&[u8], PublicKey<Bls12>)> = Vec::with_capacity(n);
        for i in 0..n {
            let m_pk = (ms_clone[i].as_slice(), pks_clone[i].clone());
            m_pk_pairs.push(m_pk);
        }
        b.iter(|| verify_aggregate_sig_v3(&m_pk_pairs.clone(), agg_sig_clone.clone()))
    });

    let ms_clone = ms.clone();
    let pks_clone = pks.clone();
    let agg_sig_clone = agg_sig.clone();
    c.bench_function("verify_aggregate_v4", move |b| {
        let mut m_pk_pairs: Vec<(&[u8], PublicKey<Bls12>)> = Vec::with_capacity(n);
        for i in 0..n {
            let m_pk = (ms_clone[i].as_slice(), pks_clone[i].clone());
            m_pk_pairs.push(m_pk);
        }
        b.iter(|| verify_aggregate_sig_v4(&m_pk_pairs.clone(), agg_sig_clone.clone()))
    });

    let ms_clone = ms.clone();
    let pks_clone = pks.clone();
    let agg_sig_clone = agg_sig.clone();
    c.bench_function("verify_aggregate_v5", move |b| {
        let mut m_pk_pairs: Vec<(&[u8], PublicKey<Bls12>)> = Vec::with_capacity(n);
        for i in 0..n {
            let m_pk = (ms_clone[i].as_slice(), pks_clone[i].clone());
            m_pk_pairs.push(m_pk);
        }
        b.iter(|| verify_aggregate_sig_v5(&m_pk_pairs.clone(), agg_sig_clone.clone()))
    });
}

fn bench_has_duplicates(c: &mut Criterion) {
    let mut csprng = thread_rng();
    let n = 200;
    let mut ms: Vec<_> = Vec::new();
    for _ in 0..n {
        let m = rand_m_of_length!(n, csprng);
        ms.push(m);
    }

    c.bench_function("has_duplicates", move |b| {
        let ms: Vec<&[u8]> = ms.iter().map(|x| x.as_slice()).collect();
        b.iter(|| has_duplicates(ms.clone()))
    });
}

criterion_group!(sign_and_verify, bench_sign_and_verify);
criterion_group!(aggregate, bench_aggregate_sig);
criterion_group!(verify_aggregate, bench_verify_aggregate_sig);
criterion_group!(has_dups, bench_has_duplicates);
criterion_main!(sign_and_verify, aggregate, verify_aggregate, has_dups);
