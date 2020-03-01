package com.concordium.mobile_wallet_lib

external fun create_id_request_and_private_data(input: String) : ReturnValue
external fun create_credential(input: String) : ReturnValue
external fun link_check(input: String) : String

fun loadWalletLib() {
    System.loadLibrary("mobile_wallet")
}

data class ReturnValue (val result : Int, val output : String)