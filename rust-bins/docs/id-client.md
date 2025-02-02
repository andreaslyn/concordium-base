This page describes the identity-layer related interactions currently implemented in the [testing tool](../src/bin/client.rs).

# Account holder interactions

## Creation of Credential Holder.

A credential holder is somebody who can go to the identity provider.
The credential holder consists only of the secret identity credentials.
These can be used multiple times to go to different identity providers, or multiple times to the same one, although we are not sure what the utility of this is.

The command-line tool can be used to generate a new Credential Holder Information structure as follows.

```console
$ ./client create-chi --out bob-chi.json
Wrote CHI to file.

```
which results in the following content in `bob-chi.json`.

```json
{
  "idCredSecret": "0b682c10f8569def5f3c0198c3393e28f3fd859e66bc26ee34e14ae6e78bbae0"
}
  ```

This file contains **private** information, namely the value `idCredSecret`.

## Creation of pre-identity objects.

A pre-identity object is a public object (to be sent to the identity provider) and consists of the public parts of the credential holder information, the commitment to the prf key, choice of the attribute list and values for specific attributes, etc.

The command-line tool can be invoked as follows.

```console
$./client start-ip --chi bob-chi.json --private bob-aci.json --public bob-pio.json
Choose identity provider: Identity provider 1, identity_provider-1
Choose anonymity revokers: AR-2, AR-4, AR-5
Revocation threshold: 2
Wrote ACI and randomness to file.
Wrote PIO data to file.
```
By default the command will try to locate the information about identity providers and anonymity revokers in the `database` subdirectory.
If needed the defaults can be overridden by command-line flags, see `./client start-ip --help` for details.

This allows one to select from a list of anonymity revokers associated with this IP. It then generates a PRF key.

The result is output into two files. The **private** information that must be retained only by the account holder looks as follows

```json
{
  "v": 0,
  "value": {
    "aci": {
      "credentialHolderInformation": {
        "idCredSecret": "0b682c10f8569def5f3c0198c3393e28f3fd859e66bc26ee34e14ae6e78bbae0"
      },
      "prfKey": "2abae44ee1223b2f21d8c0137161986b63456875cd056d788c55dd2f129224a4"
    },
    "randomness": "0fbbb352154951d631f2aeee73e2a0695228d2540a968c1e9fd95af670c93add"
  }
}
```
This information must be retained by the account holder in order to generate credentials later on.

The public **pre-identity object**, the data that should be sent to the identity provider, is as follows
```json
{
  "v": 0,
  "value": {
    "pubInfoForIp": {
      "idCredPub": "acf7de2df3e926664cb61069f5e28c3c48dc12a80ac405ee329e8720166d09c2ccdf1a07b734a1212e2700cecc21d315",
      "regId": "b29a42680dd2fe6b49c5c16b692c5afb748f8e65ec7ef7021f575409d03971262820d46a1acee0fa0549cdba77cb70ac",
      "publicKeys": {
        "keys": {
          "0": {
            "schemeId": "Ed25519",
            "verifyKey": "3017c44a4b168a2e4b756ff284231b8ef83d95ff7ec8f1d9f6e060b463120f02"
          },
          "1": {
            "schemeId": "Ed25519",
            "verifyKey": "a86e9fdb8065f8cf747e09d8a25105daf37ae15be3a4e14747b111378f50805b"
          },
          "2": {
            "schemeId": "Ed25519",
            "verifyKey": "45b3079146a6010d1e36a3f1613e66e87e3c4d4516c51cbf18a3e9d3e7dbafe8"
          }
        },
        "threshold": 2
      }
    },
    "ipArData": {
      "2": {
        "encPrfKeyShare": "b549ee4994128d38e71b0b2514d2069fe6afaa16d563724ef5f1f7fc2da346bb7b247d18421c7a9b0ed5d0ef2a1c2611a410b845edc928fa5f54c7f025aa754fcd7be441f8489d46f42dcaa3fc0e9afac8d83b574f0486c4ce9185e539d60718b99b2bfa2e3ea0867f31b0c601f00ea4ecefeec4054045a9de59e972400a39f5a011f4a5978f88d36bc74effdcc9467e8fc85ff4cfc1e9fa925f68a2892501bdc34afc9aef3738467a51379070f6bc4591309ebfd416dc1e4ae57cbe7ced1c40b89f306213c0c6152ea85011c296bd5dcf92c07fe972d740d68b430d766dd8f0f375359d072191c33c5b78f3f84350419293ad484098e21a898d97ccc827a59d93861676d8bf047b54fc33e0096a9008b18cd45b30c12e12e3ac3461501b232d8d8175abbd271b5db95d0cda1999235635a6d9b59c6375b4da1c6c8ac056e72ace6c5082a869bb43127faf86884cba14a03894f8961902b971425ff20b89687e7af3dc8cb9aa01dc49a9c9c5c73606392cad4b84eda0da5e061cadeaeb9ef380b072c56a6ce2fc941d814b889c360d4fd6c8da80df5c1c4a17a6c5a5eef12a5f037dc38e81ad8f27679e5524dc273468896139af188f4b3fb0c3cb9353b98d71606ff13c273b7d377d1b3e3cbc4e49e93fd4df91ff19ffaf40ba364997d6450baae94b6b2961ba652075463e1f3aabf369033ae04aae2ea9661da3d2d46046a48fceda995b14ea975fbdcde13204cb3782a122d5593ddd11de6c0a9f7055f2534b4d2d509abb23940ce23198825d19222e28b6eac2ca7e3cc99787d4adb38b26b1f8701f54069ed2b0896caf23eb597828efc9a7e0b3c6892e05ff1c487544d8e48008307362aa129623eca3fe25a6c8ac03afd5fe3c27b8f9f3b6836e01a22a8e1dd55410b739905e7af028429fdd7674ad2a7087d1c1516598715a83ecc70b90c164a2f252299962c6f394b213ecaa22a97e93ccc9eca8235499957f055fb6784e92fb911e72ae94852fd1731bad508fdae165e7c55ad832e7fa8b018d6aaafadd618541f19217f7bce81ebe83cecef933d75dc6c079bc8a2d8c96f5ff5a3f",
        "proofComEncEq": "5d8cc19b9a8bc83dac1eefa9cbad469adc9642fad4175fb37767ab743abac5485e3b8efa1a33132df5615dcbd81d958e1e0751bb6b4c9ca917115b1a0d00250e66f8671f2d95c8766f96a30e0dfe0a6b817007633268f4c1538e0e04584ad52e"
      },
      "3": {
        "encPrfKeyShare": "a9d162f15a625f8e2c73ddefb66f297927ea1b0e9303da9e32f84fef914868396c2806ea6f28953697f3fd864ead5a74a31d7629906f7a6d9e4ec4c4982dcea5369b3e25be95f2e056dfd1b2136cb5b88a0fbe4a334bf546e7b233d0f09e046a97aae6befa455251aa182a53300fc882b9926750e611d42400812e1894d199ab17faedc453f1b7072b689994fb44124e9666f95f89662d1dc784415a5308aa2d30bdf0590f3fd0db400bf2504737ba7c3f651ca540aa2304771d4854d0f96e4aaba77602f53357d6eb227a2f8c358073c4fc83548d8130111a58fa83de98681051bec2959f7b5d93d763fb2a8f9c9250830e7228d2752e2e9f94f72b887732be4025847c115c6633d6de18cb36e8340a80c21097cd4857bcedc482f93c5a5d9fb1f57085ce84edf7a146a500b6ec5ef58202f729e62c8eae304373eb1404c7caf4b9e8faae19126d37052c679e767a0fa4a537d001d594abfa7769ff3b92bee4b03799773e693e16d2ae822e7eca93f047d062b9247a2e234202e50f5850b68ea65f67495d734885594a597d036c27675a43ddc12480438e0022cf50a8fe40ce623b6756720405caae217c7f7a05515994fa16f2a427614c508a77f6bdc831eff5ce9e17e21e98d65c0bca24a7da29c2359574e4b5a7babab9a8f56bea9ef526ad57b5e960293398ad0b8dc000866d21bfeed972457a86fce5a5a83e0dc126b8b251402fbce60a370e780d1259ab269f9077a6b11a6942c6d809eba2c1f4c1722bf70c79fa30dd2dabe066ae8a0122dc0f9dc5e1ecf4074081f67d278b761eb1a1f21471b49872a64ad3ecf7e9f86dd0633a0f7168edd520fe2258125460d009606790ca3735e3a4f4641f9d61335f5d8ebf243bb92b5336effd1cb581aeaebc7e35af6ccc18ab6e63057532a1d0e57fa3569debb45852143c21548a4265fec3807faacc6111c4ba3f641868ae57e54563deff3e362f991ddb1ab3c4b7e16611c716435f460e6f6ddf6a6ba327c512f4a8833c41b2a41bae0ec7a8c630a2896915f38c4a947a090960001416661bc9397d7b25d2db265b71711ab0c6899d4f83",
        "proofComEncEq": "58073099b8f33180ef87f476d471f7f812a425584df8ba59ff6e3a940e6c354c3ba6707559f62391a09370267dd1ecc213c70de0361b3ffdb672caae6d2899fd03e4e4d36981b1fdef4eada44f1bc1e9dc41096101cb8cca19c71e6d1aee63c7"
      },
      "4": {
        "encPrfKeyShare": "b513c81a87b360b12ff61aec1ec95086329ad68b613571be939e77c9ab1d0fdca8a26ab6adc482b9730ce8c5301f0076b648b333b8052c3bb34e98253e378a71a0dbe8ad482d0696b1a37157bfedad0b34f50b1307814d359ebc22ce26839295ac5d1b67f806ae2329c8746577257ed31e64a77eccc4a536674e2cfa74a6f592976449607e55446fe3ccc6acffbabf6cad5a94f5e6ab19b0fe909eb154208d7ff2eb1052d36e3031bab8fff655e2f4f88b96db83839871fa432de90401453438afe8e029d6582e43902dc3e78a6d62e0fb160aeb1c744cd2773b469f78d286b0d264a0c44d74be669c8c1ea449180848801047269f6d1fdcb9c8d6ba570dcae5430fa652efb72d5a4c766da3ce5f46580e3163297752f7bf8b137fb0007fb7bab9840983359074579171450e71ee2b6fa326717eea3a889feaa12b12b8bbd2a2e1848c9ef110c3746af19120a339a32a95fad3acd6f8e38c683f1de9c76accc84b0e673f93252cf442c6be796959f3f98fd8f5cac1654805cb527e4b2d3b15638135a0ca68f457cbc8ea8e8d2de3ecb1f7ef51ecbfbab5e6ec8e167cd10c48dec019b3efca793836bd76474899748eacb9bf5e329fccab2e94da30a70e9f6a29c517a1ba8585fb4035d06e5e0d4f87d97095fbf107be38bc875988deeac719c88c1fe45fd9998ffb98784faf584437aaca78bda6800d2134889479b7208bf74ee727a8b1ed5bae3fd2873f5049dba2f58c918f4902c8f421c5221c041a895f93ef132340aa596534182be82345cce2cf6821af109c440010f161670ef828567a89cc2799b60c8830b4b2ed33c85e62d3312e0c119c47fbcebc74c72279ce9b007da9cc06d0de9e5ebebd769978330210af89d128b171394bb81d6c5d5dad253d49ba3c26c99575e534464b938c480916a440615802622a640cdd7ee1735dc6b8b4501acf859798d4841f0259484d1dc157a06ac44152ecc6546e94a0ac102241b4ebc9a2446ee3a243927f3d6f9625398bb5c8af175a847c36d78b57b039ad96b9b262243bd57936e032d32cf094606dd0f1fdc08c6a3cbb60d99cacf0fb3226",
        "proofComEncEq": "516cd3ea88078736fd2e28c5c4142879f8d67c7f4160cc1ac327e0bec4cddf5073672c0498e4facb5231f909e59b7c6e1b59586614f35c954af39844c6eade7e55ffd446e95627f8f56a8f7c4ffc7fd22f4f51c820255ee44c17e5e2f3b85b78"
      }
    },
    "choiceArData": {
      "arIdentities": [
        2,
        3,
        4
      ],
      "threshold": 2
    },
    "idCredSecCommitment": "83b83622d9006e35d369e5f7eccc1a00c094004e316036c8525cda59dc97132d33a3a2b197a44461304c43b1e1697dd7",
    "prfKeyCommitmentWithIP": "b8665c29a9251ddb9b1bf548e54ed06adf137734a5c90f79dfd8fa4d8240bce9b18b2093b788716c3fceba382ff7e0b3",
    "prfKeySharingCoeffCommitments": [
      "a821970bec70472a12ddf5942e6cbffbaf5759665d0bd843e7d322e334e3429b0d7b949a006e7ca3cb997a2143e70fd1",
      "b1bff264dfe7d836529a6d63d14b3ca6d4dfca817b42df3e7bd6865c252e1ffeb7217bed4ad8e9fe162dca4cba5287be"
    ],
    "proofsOfKnowledge": "99fdf072cfe4145ff7a7212b44dcf8ccff2d23a370aa40a0637a86684e7f25df43d8438ecc93a952043c77b0c1b619c0dfa8c17e74d461dd0080bcf125aac95702cdb031c18626cf8d429f0647c7d8ad3143cbfb12985bb0908a6f2be0df776227c1c17ffe225bcf80187ae42f127de6cec715477797552b5c5d46747f61ae8106dff3cde5546c2ed9f78068b24c1248aa93a54f2c0fa1a82cb7fc28f4e1605e6ba25ecdd4cf0bf301a0293c6cb942ea292262684766cb8dcf4aab2a8e7e6d442ad6fb6e7faf61a6716c9ea04e3e83d83c4d1b0b631926f9efbb495666d9bba4668ecdc2576ed304c8b4838dfd5a3c43f8ceb4888471ff2184856f86cc37920437701e550af3d993ce0b99c81d7d003b6641ae9be1048d1eeabea03942e24d100300c0967c1666871021262ab17032f9afbb76d0354fc8cc644d55565c58378d69c76544e916dcacf36fc13ac2b6b93d15d9c0d8551892641c7ca1bc819da84bf70901b5531a3d84fbfa831b722eead6a38c8a9ca9f469e90a461b4dccf6cbfa4b9e589a49d560b3e78584496d28343185ce13fef705f3b5d5f1efd67d123f03fee6090271b2084e7d35198640d97a8c2b18166809e86010fccba1b21b94668b7eab6b2aa28d6dbecf4469c28a56eda69b55109e07c20504192e7953fd5dfc245713dc0600000000000000038e53dafe7aa7c2e66633bedcd0551cbc2ff190116bf260791cb4ae5b3324091dba76d34e812b72fa95b4a04776ae284aaa914100f54457752fdbc9c369bafb03be68558834311be796a707ad840d6e621d082b9477af8a060bd52195042e0923a09bc0ad17ae5d5098fc229a894d923e1d951a8122549bb04e38e8f431b28c71004cc22cbe897313719a04fa15a314a3912e60802feab77ff8d9d151320bdf65b0a594d5041600bd89f1d1889b36d62747f51565bd3b39866dac1b367c548834216ae91f04c0082b4c1cfc6fe8fd76699a0f034dd67ec285d7bd3a0f73c309a53b152255054644f602cbf151459c9e0faa117886c7808b24c797ff6e6456c29a64f00197b74ebf43a243a7ee4d45ea2037cdd2094eaefd553a8f94d6c95e855a000000088e06d01b3769366fc6ed2476c03a09f0026f8cd0568de5ae78817ed9b469115b5b78770519b43e815eaa93350485f8fb84901769932968a77a9ac57b836e889a79b072d9be7c249e44219b82c468a1dbd3e0b806969d75c7f83f6f70545045138cf77314aefa93e4ab2502c8af21d7af8ae5b1da15473108bb1077e73ac69e8a8829a77f45d5edcb107cfa5070256ff5b26090eac968751d6d096c12ac022281d12da50d2bb12d3f566b5955dc5ae9f5a155def7e0acc0c2802a360d7f36880e87e90489a3564d426012493fc9ab9f60f312e8f371435013ac6cb2855163bb4ae1cef100f3d01a182bce6c1f090d8b9a9431dc66fc46da90e05958cb95aa342c64a185e0245252f35f30dd7088d27d8d96053c0275c73f29d518f4fc61d80261b4b7a421c2bf6cdcbeaf59599356b60092432f2ddae049748fe6d67b8c065d497054d9abf4440d61574e8161b33f14dba1d5bf6b922b44bef1656e14dac79a95e64df8aa1abd219cc6262f1bd1f1b595f375332a4c5853b5e480a1f6dce3be54b421cc40f6dd5494f7f485b2ae870de6c8b8aa54889e108cd2e7b2fb89d94e734abc4ac0ec2d947f9a87826fa4ae6bbfa4a7f10edae8a82e32cf2669d8874f05605a97e68208dcc7110b0591c8f891e0c5e9f2fc06ea27be9667097af9f5051a95baee0fe837d609941dde0d8cb7d13daa6b5b1030fbec18898a7861ed4642eea79af19cc04ce29aab0185fed4c3159aa47ffadd0841275b8aa346e41bd10e6ce34b7ee52a930d063ac244dcbf548120520e8aabcbd183b81d6c4a9ec3980a39b28154bcb5399c91687f70f3834946d065331443b072e4eabd9cd088949340c035a1463e0fca16986d458ea3f070658faa66dcb6e4facbfeeb2b74551a439cdb328033e30a47e9320fa841bf1874b71d9650e7a087a85baa54c67790f63ff8cc98f45a22f8f34b4792ca6affec7975389a198354f2556bda574828d6580434576b308097656fd865e89ea4e5bf254c2db3224340790a7abb005e1f5e53690c82d5908de0e9fa5ea3da7404d8fd5dd9b1c09b55be8655f9e14e680adfb1082c9e2ae2dc0fcbe67ea533fb4275eb0802e5a4cec0a261ee5e55a132f552be4c77321be5ad57e2a7cb48620e8a694d6bbecd132f4a656c07084d588a99d0edabdd9699d30b2834de7c9b399694544ed2e84cfc15ff631cd9e0daf72af0b16fdd620dd011aac977a095b722cbd08ca576df79b559a35ac686857fb56c67c63504cbdc5dffda6eed0c1c771067d78d6aea7a0c7d6f4ab631557319c38472a97005588eb33749829aebe2af5a8e5f6a7f1e61f77dcddd852c11ba2eb74ea597ad4e8871242b0bce9c19a8536a185ff8c5e2a2028dab69241f04cee9acd0879cd9fc9698e7d8a89e0840802b5822f4c994ad43d091b5673eeaea6e12b9309e8fd848a9222cfef42c0aae27c802e994db290c40a0c9794f6af1bd3ae0f6ef22ee907c0b310e345a4f334246c961491ce4d1525fc1fc0c97b248b4d983e48b8076d33234ae0f40325e9cd5504917b66dba4e1e5abde6aec00298be63cce13af3fa9667251b00000008b8233bc00d2712ad03c2786bd4f95b60dc1c490469f11ed2631a4893e640ad2afe0256735323e3043fe7b818422b25a9b3cc6aedc029133f0bf5964f139c39e920e8ca7147717ea5bd36be4ac72ecc2b48a58ecfd3c00362769791f215df7d408eb3d89ace8799e3300e5c0787cbc8c482aa5faef2d5e35ed392c5973b3185ee6922c7aaeb36652f0cf7c66ad6758563a0cb4cbdade96165c8b2e5a2009bc9fb4a4884c607a3fdc46f0ed9f225ebbf23a417a3bcea6cc6731a1cef78809e9ed2adeede2f5ff57f1266c652384d02ac90927ba96c9a3922adf2802769669905ead362349f35f16ea574693cbed1eb92a9a7e4e938e5d443b8f83b70bf1523c860775489ea8e529422b91458635a8c23c93fa8d73167f9ab94d08e4fbeb8f555e8b5ddf0c3e78fca6a8ca73156f052e535847989efb21a52b917ed51391f42d75e761cc8927c552dc8a2732f4da5e0d7d7b8b9f007f9d40b7cfb2ddce6702d701f69d54b4d317d032160742480ba8701b3f5a8d449152d722bd9b4ee119ff5f0c4887d6f18db7c6af71d39dfd36104739098bd0754df043b4a3df15cc991d801dda14493977e912f4974bbd7b3714ba6c9902e8ece96cac53373a8056f2299be1f7aa7548c958999092f822ee711204d4fb03c788cb1a0a974d8581f702636a323954aa16307f6535c27ceebb69c71ad59a930cfa97f03ba3755970b01744f7e1d2dfa5c593deba145253b8f09d4079bf18f39b6922bc12340af0e691b998852189408cd308135925809faf485c22a68a5dff666feae7b818dff5e6497a5adc64aa4265cd069d1150f93a23a59caaba09768893bc7bfee775d57ccf3edb14b167e934120c1fd4ce12d8dff6dd65625d9a889b7bd722123d9be1fd442e98b186a8788ac9b3e2a8558cafcccc977aa7764fc9365887a9064df4be6e62e30e146b1a5b57c4cc1c6b71f3d53f5c32f259a2bce1cc85c3cdce55ca84c4ee349725e492d656e19a0e4d0489ab054d696a1f5e80fa4b2e332e1b5a32cf0cda84693f6c849d4c26c3374825c15a2ee3b5bd71bb4039298ebd7cb99fe0139c39b360a64e9b5584eace137c8221d4b803d5a8a3afdd538b8eb5b6b6b18a23e49f07d4d0192dd1bb3fb9248986aea30236080a4ebafb298f8ac5c677951004cb8ee70291b90ef8efbc8355408b0d447bec95dbaf4150f364ec3c8b9d2f5242ce554ddbb7080d165dbf4e54aabca493da101fc919cae7e8bd14a448f30548aa410d907d3d8ce8e0a1314c7fd166c5406c97f60d3c47fb5869158eba79b24f12d5091cf2391c4eda6e12ce56d018f7d8f3ff13b71206614aae17bced0a37e7dd9985be423db229856ae408c09e4b43df6c571536ade542d8a1583930bee5aeccee3a3caaac63ea00d3df7656b884bb8d73f9df26da156c0a4aaa19b2bd43a5087cdb9c95fc085b00cdfb9f8b04307d437fe3650b167941a9587f91cac90447d0c699538ba660de55cf97b7680d14d0d76398fadb4d44c7d8939c0bcc1b638d0d9dd98c08faf14a93b3d0b0a50b488ab5b1577e7847c9e99d758927c5035dd932e4b5707ff67b74100000008a69d2f459cd9e5fda499677a49231da741520beb96678f8e7eff57ec33d00a3764e2b8a535c8fbfe8cc3eff42e05bc8088f64e79ede720435524da3521a014f73654941e9fff18aecdbdfc833fe777a695dd65040df2fe28ed45fa6ba96696bf9444eb5a0647bdbf41b85cf60c7e52add9545daac4aa6c60076eff007ac3fd27bb692a1c723df5e6ef31026826b6c20881a907378294c4e42b0143637d6b0278754fd5f66281de5be80970d65a74d2ec03a5b2b8487dd0eb1fc2140e01950b32898b988e31e1ee27ea605d82b56ab0687ba19a57ce7cc6f1ae083f004b8c036c3f8c9829110f91d5050b4c851308ba02aac6de38d9d1da713ab888b6c163a1a53ca31978254defaee63f9b551e2c792a770ab8fd58780af44c9f002b52c290e682a70bedfcd1c2de142c65ac40ad82ef500f3f27e6da2eba72bc697b6d6f19931f60799d9a22b0b6ea3975a3dd5cbd4ab6f6439db8427ae0e0bd68196b938d653c92cfb39b5e5ec3382e5c006a32c4f3679729f4c6b32c1e38c0bb10df8bba67b3519d3fea04a1af7045537445aad1fb6c9d97db124c5a5be12031959867ea2fb98dcb300cf7adc1950be13aa6d6b32f9001e653968ea261d1baa18cccf1d8888b302dc102f2bc4781cc0370ae4e58d17bc54dd657384cadf68e41b306485be1a37101fc354f485f823bf29ca982f7710f1e9f5a641b3e3864e90be65a9f55bddd6db8e6a827444acf3abf9ce77b3bf5ae26219cecba184631c870bdbbfc95b7815e373f9136cd8ea75fde6d0206fbafd1d98abe8743b987bedf28ccdde80fa68b7153e14e0d6821ab680b8b0e8f6dba3cdab69279037a7ab2749fe4f60637c1973e87c4b5c2400f4c79c8a81f6c45ea8cb88260b0d8429f98cd18745a270489d8ba79f64f9423297534da3ca7ee119bc40ea2ac3640177fa15954e8f610ab2faef67851a3e9317df70c921322ff3978610c55cb3aba98e45d6ac66b3b9acd42f61b224aa1c5c61336e93a6fe5289d36a9192a12433de26496f3f698bd508980ef9ba1b1cc6e80490a8174aea25f84b0aa175f777e3bb9cdce30b198a54f9c8b13875234a3fb86710ab740537ab231a5b3144be3e7307439c778b540e7fd7eec1d457467fcf77f7c41f34843922f057d7ed4ac5619ea7fc8feec6673294203cb"
  }
}
```
This contains the data of the request that is sent to the identity provider.


## Deployment of credentials onto the chain

This is the last step that is done by the account holder given the private data, the signed identity object (see below), and the choice of which attributes they wish to reveal.

An example interaction looks as follows.
```console
$> ./client create-credential --id-object bob-identity-object.json --private bob-aci.json --out credential.json --ip-info database/identity_provider-1.pub.json --keys-out account-keys.json --expiry 300
Select which attributes you wish to reveal: nationality
Generated fresh verification and signature key of the account to file account_keys.json
Index: 3
Wrote transaction payload to JSON file.
Wrote binary data to provided file.
```

This will output two files `account-keys.json` and `credential.json`.
The latter contains the public credential that can be sent to the chain to create a new account.
The former contains the secret data that is needed to use the account, for example the latter file looks as follows.
The key parts are the `accountKeys` field which are the keys used to sign transactions from the account, and the `commitmentsRandomness` which may be used to open commitments in the credential, or to prove properties about them.
```json
{
  "accountKeys": {
    "keys": {
      "0": {
        "keys": {
          "0": {
            "signKey": "53067cc17c5f61e1f96dbf652806b371dbf9c7e832ff79b1e03cb9bfe00965c6",
            "verifyKey": "6d0487362c6da8127b1d20f50f4b26a49a12dfcc672e4f9704cb722babc43f34"
          },
          "1": {
            "signKey": "4512098328adb8e9da39ff8f6c404e31e3edeebee8c6e83925f646923a593a86",
            "verifyKey": "fc5acfc30f4fbac8e289758174157e89cd997765c71700c836e336213d24788a"
          },
          "2": {
            "signKey": "e5c779491120eb641e458aa2007e39322e657b934d35d066f5d81191138f9a4a",
            "verifyKey": "54cf8ab437c4215c8ef51f95f9f1fbbdcc65e84ff7d6fa3e3215a06c5b099403"
          }
        },
        "threshold": 2
      }
    },
    "threshold": 1
  },
  "aci": {
    "credentialHolderInformation": {
      "idCredSecret": "2609e9e9428e815d6537788c7f9e2bf11776400aaaaf13b23f847fa0a90fbcfe"
    },
    "prfKey": "1947f2213fc8b139c3e4be6fe7813a446d385367f6a8b9568bf60ebe8052217e"
  },
  "address": "4E3fQGXGFgDZpN79WcS74oK13KUbtjgYG95xFXs9da2FsDKcQ6",
  "commitmentsRandomness": {
    "0": {
      "attributesRand": {},
      "credCounterRand": "0c6fedf6dfcebf7b6af0cbd42a96cee531b6d05393486f5589fc90cd7ae3d3d0",
      "idCredSecRand": "552365eb162657380ec7ffb5d2c909a7b18af5bf8536c0a598497d1ad2b24a41",
      "maxAccountsRand": "32107abfb6bde1dc5a6017fe706aef32133a31db3449cc6e46ad2e9c1f6c849e",
      "prfRand": "114cb109853a1917e6e236e2c3648fc751a8fba324532623d9086e47ca3f96e4"
    }
  },
  "credentials": {
    "v": 0,
    "value": {
      "0": {
        "contents": {
          "arData": {
            "1": {
              "encIdCredPubShare": "88b8a4e09ffdfddf722b4434ae7d9149b44198a2d237bba305f3d5e61ff2b3738b24ce75295eb143a879c7c8d787ef6585d7f38a0a8ed886bedb219de1c064e959f8cb6a86240395c8504c0a549e79cc881cb93951998f8e94361ccc90ed0b53"
            },
            "2": {
              "encIdCredPubShare": "8e8afc9271082e12d37a5e34023830e8b866c608bcb09a1d712a9c9c87e59326517445f5621ca9eb7535ada17dc838ef8de2731a9b1ff15a3b1f53b4ba22e88d2d8165b12ab6f9497a0b8c5432f4c8f6b0f739a8a52e558ec96a50ca64ad8a6b"
            },
            "3": {
              "encIdCredPubShare": "b2451a5bcaa4a99caa8796ed7d8906bac644307182c36494c655d2787ac2bdaabe3ead6d2ffb02eb1a30b959dddec09792dd7960649007361099eb78a2e400ab7716f524251ea6fed987292d974fbc72a160d9bb751602940479c45c7b9e6923"
            }
          },
          "credId": "b1007ac043f782e1ccd5ec0334a31f9a09c89e14dda283dc3e87aec4c0e8bd872d24cc97c62e4b5bcc85e7dfc5d8a716",
          "credentialPublicKeys": {
            "keys": {
              "0": {
                "schemeId": "Ed25519",
                "verifyKey": "6d0487362c6da8127b1d20f50f4b26a49a12dfcc672e4f9704cb722babc43f34"
              },
              "1": {
                "schemeId": "Ed25519",
                "verifyKey": "fc5acfc30f4fbac8e289758174157e89cd997765c71700c836e336213d24788a"
              },
              "2": {
                "schemeId": "Ed25519",
                "verifyKey": "54cf8ab437c4215c8ef51f95f9f1fbbdcc65e84ff7d6fa3e3215a06c5b099403"
              }
            },
            "threshold": 2
          },
          "ipIdentity": 0,
          "policy": {
            "createdAt": "202109",
            "revealedAttributes": {},
            "validTo": "202204"
          },
          "proofs": "8fdfe5df851f6c69b4d3b9d1baf3609604381172025721ba2e32ba605978b0101a091177f554395beb6f7b4b27315c2eaf3a43dee7e2e71d02437809e8f326312e1824483b6c4194b1e35b5458bfafbbdc5a672e35845da106e2265ed99fb815970d0230ca48c6e8edbbcfa745b8100f70eee6e8767d5458257842495f0c4ca8d38f35ac121054c81f69781bf70786a38fa3dc0460ef35da1656f800e830f7454af158c5a27374ecd7983d3563f2762ad7751db1098a2125d49763e51c410e61b68c54c344f3076602d0fec969ea61e70f7afeb903abac6568b88f24caa66d56afe5a66ecfda72f61cab524fec1d02ea00000000000000000002a6640ec2241bada5b0ee57c3419bd8c731e704c5047f1c070bb9cabaf283a8a0253f5cc31aa94148f1d0fbe22c37b01a82501df8c3f9d73935eef2416400c3ee3ffe7b342695eb8e0462ec07ec3e26c78d0d8c1e01243d6a3a2b5d85eb94ce13fb1991a83a4072179a06bd6b60e05c3fd5981dfbac73f5410df3033af8075d75000000030000000152dc2f2923c23fb64f2e87e81190d123263bfad88758d60d0b6c10716ad6d43f6958776eafa41bba980452d268991c2d8231866d8da1391ad0b43a04953171613f124fd8b547b01b97da1e3ed37df597dd26d6f66a2ad332fa86a18f54d050910000000225cf758383965e718a14cdc53ad8e1a9b3d109aaf4ad504ad247dd424b9b40e371a5ad19cdfecb541a9d8c9dedbd0df19f0c5dcecf0b1850c806aa6c1013fd4b1b5a442743e8b3e3b1bd75035c10f632c645a4974ed32331f9cfe31b2ccec49f000000035949226d5964e1fa5ea669d54386ba5d31aae3b051405469ac0899e8b83e9f3a13133e6cfade1bb0f78ce9bd7d2365052657f5f222653b56e806e5cba9130cac113a34ce14c90ec25110bc5bf9468a1cf3d851f937a5f6957817a72e37f81d3f5e48724edea09b73743860f5f64634a82c273227b21fd37c7618fecccdf4d3f8000000061f1ad0385eb8b5e0f21f4ba8a467b1bd2d00a9acbcd213009dd5504cf6a6d79e3b424362a5064743c108264b9a650b112e95d0379f033e7b59e20f28553d59515d794f81664c89065d35a096700ddc337e4b90df40e454583a26dca721d1eed85c07b95b779a151c9be424aec7ea11832203fc20ccfd145736dee358c29471265d3b78e2a8e471835d3c352bbf8d16fae3a6d781118d4e56a8926acce6dd09553b24e24b680c037983d4a9ff15d448a0075cd570507c2055de9acbcbefd29ae45845249631ecc3bdd76793232df021a626031cef00969a3d08affaca431a950113c2929f594a3a6f81bc6edd5632a71f9b0f54d1f88053baa0d1833e3272e6175b597e034e04692187f143c726eb80ad964f6c295f4866bf590af9780473ddc3032b2d8009377e11b454d2c0d420a15218cdc40dee97560e2ee2956b0ac8fd256674d095d1c720aa5cd012f146c13131af853471ba7f4c56508fa9768da71b3405faadb8a7f1a839fcdbb0e492297421a4f38884867bebe1a3810e263fa405d245f1067c46d39901d3657e69645275361dd0ca09fc72ae5c7e898a14da0775cb5130e5f70172cd160b19e67a5df4fca63a1033b99f486e3b6ecdbab318ad9db705054809f171f8340a1f483c56c255f0a7ed04cf655df6a997724cd5bdd5b036141390812b9bc5515ef69fe76b69adf75695fccb9a5edd057be68ac0bf44a95e672ba0d4907b09490e87003ecc3a17e977efc9a3add90a3f49b31e2000c02c470300222409f9373e943476ce279f6b6f62a58924a769c588638fb4f241e1c594dc0ec75bdbe081f78db577b87531b96235adb448e30f1b37b9c0717dcc3433b9a80e011cb605810ffc6a08637c7849c4e7710ef3f188487b777b79e41ba06327707e920f5357035a11e479707d93a90e4145a709ae0ece39c3d5b096762ae95489780d028626e4009ca5f7f033b53c0579a6ef19bbe56b1b2e9f0e8e94bae4f415bebd5c415d2451ac4991e8f77c5d3880f5464a3c3144052d3cf11cb5816399078de7069851ea7ed9c90f84480ecfe244414c0cc5c5d8204f444fcf2f54a6e47282de2fe63606524b6fe59da63e7183e2ad4f21b293a32f7c2ed6d70785612d260e9f092696ce393516eb13226f0f3b270aa29039badbecc4a90c2aafcd4aaefbc364c6a1805d0f60b2f14f90a1fb303b9f2388263099490b45a5c4c51f7de1d73b9051fc67a964889c3d25003c574be66e960e91d1e2f7d733ac434930394df2ed2418ff85d372e2a9795f2bc7ddf68ac34d4bab394758037c2d2ff817c2b6e83b851f66724c7aa4ee73810807a8356fbe887026d66a4ea9788ad1c80072d35df79fcb5ff951aa49700c69348737d07598d77a85f9780432a83af7a171823e0750444f2518269f4a9c54e40ee0860f30bfd7a4d00ee76937b8217ca396cf86c2db1a3e000000048a75fe1bcb4e76c53e3f09c6c4b57aeb6a4c96ea69650f573ce020778e097b66d3eebf39701d4d95cd629bb3bc898f9f83c0eb9c331589f97ab7bb542e858951e28283627712bc030aa2ec98be26e0d1b578dd447c7d43642d94d76fcf5744b1952b9f4d64032d07c7b8a10322d1d39983dae79b86e58633914906fa0ec2ec41dd702e04bb45391a7b055409ecc2dbaba09176027a1ff013d93936a5e8c3cb08b76547322c2b52943d34d39d7f3b062e54f861a2cb8f1a19000a3d4af8b093b09381e6d813562886f20d3c04d2f427f9b2b030938041a2ed2394dcf1237e453db138d4b8c5443b641f1e565b222b1f5ab8f51dc0c948145ba31750f2abe96517bc20b817af3ab21ce95cee4aa965974340bc576dd0f4fde161c0692d59e3bc50a5a9b5e3194d1ac6cf95ae5a35be63a9f2938acc537f93e8f147f6641f8bc8faee9f3c27a8df18b41880cf1995ba9023a15265d38f096b70ddf8feffc1fc1f3f6e4fbda2a841cdea77e5eae2f3515373a4ded8b5096dad68a8c4105ef3d418a2294c5f592e263341a6961d6cbcc53159447462f3b0a3831627bb6b5f3e12ed926d7a7a72e0eda0b21606851f5eed68abf102cbfd307ae280e8c7506902d5934f",
          "revocationThreshold": 2
        },
        "type": "normal"
      }
    }
  },
  "encryptionPublicKey": "b14cbfe44a02c6b1f78711176d5f437295367aa4f2a8c2551ee10d25a03adc69d61a332a058971919dad7312e1fc94c5b1007ac043f782e1ccd5ec0334a31f9a09c89e14dda283dc3e87aec4c0e8bd872d24cc97c62e4b5bcc85e7dfc5d8a716",
  "encryptionSecretKey": "b14cbfe44a02c6b1f78711176d5f437295367aa4f2a8c2551ee10d25a03adc69d61a332a058971919dad7312e1fc94c501f9f8aab556510771544773fef6540da426a000198cb4ff945f96a6ba4a1fd5"
}
```

# Identity provider interaction

The identity provider verifies that all the data it is sent (the pre-identity object) is valid, verifies the user, and supplies user attributes.

The command-line tool allows one to act as the identity provider (provided the user has relevant keys) as follows.
```console
$./client ip-sign-pio --pio bob-pio.json --ip-data database/identity_provider-1.json --out bob-identity-object.json --initial-cdi-out initial-account.json
...
```
This will output two files, the `bob-identity-object.json` file which contains the identity object that is sent back to the user, and `initial-account.json` which must be sent to the chain to create the initial account.

# Anonymity revocation

### Revoking anonymity of credential owner

The anonymity revokers take the credential object and decrypts the public identity credentials `IdCredPub` of the credential owner. The identity provider has received this information as part of the pre-identity object and thus can link it to a person or business.

This interaction proceeds as follows. For an anonymity revoker to decrypt the corresponding `encIdCredPubShare`, the command `decrypt` is used as follows.

```console
$ ./anonymity_revocation decrypt --credential credential.json --ar-private database/AR-2.json --out decryption2.json
```
The flag `--credential` is used to supply the credential (as deployed on the chain) and the flag `--ar-private` must point to the file containing the private keys of the anonymity revoker. This of course means that this interaction is done by the anonymity revoker only.

If `credential.json` contains
```json
"arData": {
      "2": {
        "encIdCredPubShare": "9594becf607504988ad6ffb9313fe42f66e3789e3e14d136e108864a800c643bddfa3b2fba16c697462cd540470bffde833c6ab5c2491009290920e1078de96ad3deddcf435e865febd4d417667a1c4d2f72ff1a6e6f5a5567a0aa57d193abe1"
      },
      "4": {
        "encIdCredPubShare": "af33b54ac4deb8108b6eb8e927a38e600890849376e9fc3aa3f7c406ddcd49cff7c6aa9bd79e7863b2e878660fdfcf8887af580f15d6566e101e99ac0f9cb0e5112c458870bb9759c7705f79d9f2fe81f56395f1bff7ed69f68dfe19789fbfec"
      },
      "5": {
        "encIdCredPubShare": "88dd0fe338f4bdd6b21165aad92b16c0f6a4c356cb8bd88733fb7fd9d03673b1b1bef38c64bc35519b102123f65423f0ab099967c815e01036c88e3f80dee4db71bd1461e2678c0a274830065316598a76ba763681ffe9b93e3c6f554ee349f2"
      }
    },
```
and `AR-2.json` contains
```json
{
  "arInfo": {
    "arIdentity": 2,
    "arDescription": {
      "name": "AR-2",
      "url": "",
      "description": ""
    },
    "arPublicKey": "a820662531d0aac70b3a80dd8a249aa692436097d06da005aec7c56aad17997ec8331d1e4050fd8dced2b92f06277bd587579a98aec3015ab9cf997e3033fea09ff3cc7558581f5a31f79fe59db32842f7cacf0c15f1be4975ee886e0573292c"
  },
  "arSecretKey": "a820662531d0aac70b3a80dd8a249aa692436097d06da005aec7c56aad17997ec8331d1e4050fd8dced2b92f06277bd54202ab1f9d0f2cffdcda2091873bd44a7793f8ac9d34081dff36ac6f8e7102e4"
}
```
then the decryption of `encIdCredPubShare` (corresponding to the anonymity revoker with `arIdentity 2`) under the above `arSecretKey` will be written to the file `decription2.json`:
```json
{
  "arIdentity": 2,
  "idCredPubShare": "8ac991a77761a59eeef28c4c013ca55744f3d66ef9429360ae2d34d5e272b3a49e918d70a042c54fb1eabefadc765d67"
}
```
In the above, the `idCredPubShare` is the decryption.

If we also run the command
```console
$ ./anonymity_revocation decrypt --credential credential.json --ar-private database/AR-4.json --out decryption4.json
```
the file `decryption4.json` might look like
```json
{
  "arIdentity": 4,
  "idCredPubShare": "aa1f3900187c969fc737d408b85b4af1712f579e3fa80c195f0df3a2d040b8928984084c6949a5e2b754d57132f19dd3"
}
```
We can now combine the two decryptions to get the wanted `idCredPub` using the `combine` command:

```console
$ ./anonymity_revocation combine --credential credential.json --shares decryption2.json decryption4.json
IdCredPub of the credential owner is:
a0ae3ea7f6c98488933b19113b9dbda44e08c0b28c9475a2a30f54d6ae3ed260257dad5861af60190ed10089c06238bc
Contact the identity provider with this information to get the real-life identity of the user.
```

If using `--out FILE`, the `idCredPub` will be written to the specified file.

If insufficient or wrong anonymity revokers are supplied the revocation will fail
```console
$ ./anonymity_revocation combine --credential credential70.json --shares decryption2-70.json                    insufficient number of anonymity revokers 1, 2
$ ./anonymity_revocation decrypt --credential credential70.json --ar-private database/AR-3.json                                                                              Supplied AR is not part of the credential.
```

### Finding all accounts of credential owner
First, very similar to the case of decrypting `encIdCredPubShare` described in the previous subsection, a anonymity revoker can decrypt its `encPrfKeyShare`. This is done with command `decrypt-prf`:
```console
$ ./anonymity_revocation decrypt-prf --ar-record record.json --ar-private database/AR-2.json --out decryption2-prf.json --global-context database/global.json
```
Here, `record.json` contains
```json
{
  "v": 0,
  "value":{
  	"idCredPub": "a0ae3ea7f6c98488933b19113b9dbda44e08c0b28c9475a2a30f54d6ae3ed260257dad5861af60190ed10089c06238bc",
    "arData": {
      "2": {
        "encPrfKeyShare": "a3aef0d963452adfc02370f616630b0624830f697a91a9785a62261694589027f95dd37c50ea85ea47f30be72cd91fbb8bd48fc0c980d6c9ceeb72b5f388e55adcf6e7a19f747df05c758bc0ec494f008fbd345554d49f96d7f7c2d7410baafdad65ff13a19aacaf394620a0431d2cd402bed2aa8f1481de0c47d72151d91e2572542b22aa92b48c381299eb5f2f0409aec763a5dea36913320c51d29a74431adffa1523b2397b9438fc59cb965395c980f1b10d54f70744ca8ee44dc1fbe464a62de9659f0a143c0a0d46bb7750f4144c22c6b8301bff997b8439c727c797a0de3c671379fab6f042c0bbbea1baccd488c8dde94ee5d81416b842d546cbc7ed01713f7c650fb09440feb09a33177988ff86c309a5fed4673b8cb0c17bbdc5648680cc6385a24b3935cec879bdcf3e5c3febd039c5e070b697b459eec2ed6e22282f758bcea0f9338224ce48df5dd8c5b0fa26d9e6b04c036a7e52cf3f499c6a63d2d89610aa56bef77281d0325bebda950ade1a429537c252695628d8b97309a8730a4738c26660e423d549b23470fc473301992cad819152d41d6d380d17dd6f2d8d378d064b6919940b35f0ec0ce9888c6468165aab859b7565b05f700cea0d9bfc54b145e51688ec6ce283952478106fe7652c5274dfea1ef5c9761805c9878a80a530f6d6e570a193bc2fbb5d145f1484b2f8b6694c6309ed44e255ee33a5e65030c83f71075faf22cc7cf758fe99aa04220e36cf53674379ceaa5dccfcb7b49a7d166cdcd27ecdd8e8e18aebecf6035bfc61e57ce993ada581b86bf051a6457ef4e1583da67f4a9ff9de03a2291e30e9a8e062609ff41b6ca7f5959ac45869c6aa5f17bd622cc2d8a78fda1a7c8c8a9cd1b1565a8d934a2e3342ad9d51a4ab309e5837586e062b2e3566923c8d55008a7f827e0a2a0b07e1008dec3ef5a447018012a976090213083c490d9929f329b33e9d52775656669a46cebbb81209ec77a8f0b8cb58c63fd19c1518e7278577cee115de6504bda85814af71b659a916af200f4202a8963b10857ca6d093828ee6936e0ff6ab3cba2adb524a8e40",
        "proofComEncEq": "26222a99bbbf21060e049835708a5bb3a723587f5942c2fbcdf30993ad1b31a83b4baf1c463c9fa2285023494f23cf37deceda3c13236dca059bad87cec5c1472b45917bb7e7756aee32e0aa8bd34889f17809a73bbf0b213dd840686ee74885"
      },
      "4": {
        "encPrfKeyShare": "8df039ae4fab7493bd9a7b9e6a8a202103f38f2be29b8f5be6fd217564b6c51a30357ba8b4a51d8145fcec067dcd84e293037a793aba04f91bb679415e9ab1ad2488f0bceaa2333c2da1929d797b2a3a61a59896d944555316c0a671e3287344a9c7856c113689a710b374285741c932d7b028789de705360a2c38a49d050cc40a5917f302633115fa6983589d93a8d292749aade6e000f23238c6320bd0c973c4ff48d56252f6be06b69798b8fa1dff25c9102167781dec9727ddcaf49e9464b8300965a8d49907b886a6e55fb61220e1596778245bd74a342c72f188e1beeb5246dbadd38bbec85ec341c4ef396ee0aab80e0f0852515f79b3bea81d8bb41e1e8bbdcffd071743fa356c3c9dd1a4728411e8dcd98a04a797da4a48062d0136b0ad2b69eca9ac0fd2c71c231ad2c19442d5b9103d7d4d4de2d020bd1bb54fa18942cbb93a4cfbcfd90999be8c03214e98c18698a15b6a1b050fbd7f2e8a8a23a9e5f57a38231b3fb1281552d2f550ff8ade5b23fe65a70714024e2e00dd6e748e0160e85f212f20927d2aeecad358e3110e3962dcd7895302923b8989dd6c7619e9944b7c31722db1bee0eb1b6f6f2e96774032e25841174b1419fcc898d5175ab8152d0ab700279e7da14e1ecd27f8243384f54d2aad2bb3d80c31e3f7bde29058bed815f2f693e01b98d0efc2792f0efc86e31199644021ffa8951fd790f2460dbbcf5f7a2f60c7137290930148378fdf1ca9bde1dc1b91cb366cb94c57c407ce56c4beab39c96db7f00dbc57cf25cc5ba063bdbe5da1da299faf237dd1c18d3b93c8cc324cddc6e13f70fe463e09bb0fa1bccb06eec2c1f1112314ff9d0d4e7ce12ce8ee2cc02ba8f3300c5c18398d9062b37aad41edff192cb80f5d9019506369b1c74161b5df3dd614946b9d618af8b951214008e91cb36a458a8c2b59ae079d0402efb62e84f76a355069b172e44b8f89c42000982c409dc4511726463b5ab8900705409d134294d10a4fe4d7b90482cf12075482ebbb7f5f18134b75bd9a27f05b438c054a7d823fe38bb827dbfe080cbb228286686b1ac9eafb567f",
        "proofComEncEq": "5848bc818ab6d5798c96017163ca13168919f1de17012cf43fa33a9e25d784ea445b7c095acae94434e2b1e789b3fecd9bbd6f8a944f9adf0ad4494cd116401a48a3bff9c21d547f3cbc8aae71a1528e054b20c922df3fbc9d47fe6e670879cb"
      },
      "5": {
        "encPrfKeyShare": "87c401ae5ff78abd94e03b22b6da29211f35a413168ef9d00828beaecd0082067c6429e4389ca6c1b6a2489b73f03f9d95eee585fb4a72b12fad9c3d54429e38381ff0fbcd9da517c8ed45409c31a0bbf5a425a951c56f55bdef93d6d240e8448cf55e481e0b83159b81b6e03586e71233e5f49bc7f4c61fdf2fc2752828c3e649c38d2d7ee0460806fd88752a653defb85fff80422b2d1c64a4fbf73e6995cbf900194ff13fabc05a4e37efbf889ff98891245994cd314355f0c45c7468acfc92090afcbbc111a5a68872ae6802ca2bfcf54d2acb4c7e2c39cf678a07b9c2689174963b6629b65f6c89c3c50430081d85c626f43d44b6a85a0c8b3d96e67ef38919f79e9bb19e347f6babea0d303bee307ed3792728ab6e30821835b0388c15aaf4440eb81111425e16514c0954045996a8c4d4f72c5134212855995772e0b1e8a8c5df31bb279d2785623fdff49443b95351f96c71f0d33dba50e467027c490049915efc05c53e94ba179fb181bf470e4e51c3d6e40eb1660e4cbb4d9990358e1ce66f4f1ad324a014b98390f48d6f91aeee996df78f90ab6b28b02f83a6bb6a722944087aab694a0f0a081d22ba0b92e27083642c0b799f28ea5f5245ffda0713b0574a1c138f32d54f7b05f2a474a8d980a08115e64ac4689118bfe50393b534b325efc8c4774c0a0a11eb17ab499840dfae4952123b38476891f0fcb4264f8bb75faa1c332768ce422f1f7d970194fc531d7a778786f19274e81bd0a97ef7fb83d96805bf9e702c35a6d4d1989599700d0184999a3a0cee82252b981a4db03d46dcf5eca9b521ea1fcceaf77270c9aa61f8ff403d7bf7e71747b079c6c3b236e65f39f4e3f9bf91b1b0a94c53bcb901559cdf81345a6c996d720159331e770225ffdca5d2bf11803f7351b31f819e0d18f8924fe97fde62d3cc45bae2db960888f6c9366e5c0ea635bc224e8f344249ae70a7d407792147968d2a7f8916dde607819a787f7b678e6766f6e22b168cbdcde0aaf0510315b8d37d2067b3a1cdb0f5a4058547279c938a116493fe4656d0f323507f4a4e34687c74b49451bc",
        "proofComEncEq": "246a8815c1c98f342ea5904c58229ea8254aa5f11413b7929dd0581bae8223934e4e82eb9aae28ec0da586f345f0964c9998ee46a7b5d56445e4c4de22893fb546e7824c66812abcfc4694be353c6d210f0652392edbb0d5e7fe576046fee96b"
      }
    }
  }
}
```

When enough `encPrfKeyShare`'s has been decrypted, they can be combined with the `combine-prf` command:
```console
$ ./anonymity_revocation combine-prf --credential credential.json --shares decryption2.json decryption4.json --out prf.json
PRF key is:
6cbf5790a517cf73f7728f55467540ba8f02c68b5935730bd4739c580b6bce4b
Wrote PRF key to prf.json
```

Now, with `compute-regids`, one can compute all possible accounts of a credential owner:
```console
 ./anonymity_revocation compute-regids --prf-key prf-70.json --max-accounts 10 --global-context database/global.json
Here is a list of regids:
[  "97cc03d7d0d4de3c0e39e09bb11585bfefca24533697d754bd8cd6d28717f53df1a36baf304b2c71235d0879067199ca",
"930864780b7d26d5247baceed659735830606c64af2e58824a4a771823d5292e6ef7120121d6a431e4009617e006a7ce",  "992b4e027c2e79dbc66b2f24a1254629f12b3f5d288cbb01f5f557658f7e1e7e49551e7a1d4e8bd42f0223ac0481db17",  "9219dc616a02abd0c2cf56b3477b70217ff4350b20e563aca155eb4cdfeba005b6c7c587b2d8e800514f984132119086",  "b24446dcde8e5e4abcdb8e7e5d73107eac8c7782519a1015d9edad843c21604beb5ca42e9ae1bb36afb73c358cfaae69",  "94ee9444996fb3306db44fb6c5e4d538405f987b51e968755746f806b5a43f371e9d71f30b50f0f457f7f2345d33d5ae",  "b1c3d568a2c8e25a581b350c70c95b64625336a7ae8fd14d954448d3b2940d1feb0210acc45aeee9f80acbdf422809e6",  "84572f1fb6a464cfe6f839e3b8e6e6578449805954819dc8272d718f1e131a5b3ba719807c83dfcada29c65f991a48ed",  "b87433537ad05c3b93cf4060cc57f10f9d9badb17b5dead9a150eb4f59a6d8451df3ea0993ac87b27135fb529b949323",  "a773af2d62863c0981fb7d6d59aa1eea4925c9e4d2605b6f6d5fee7d23cc67a04366881aba5e9c90d4f4f1e0db0df839"
]
```
We notice that the regId from the credential.json is on the list above.


# Data generation

The tool also provides modes for data generation. These are the commands

- `generate-ips` which generates identity providers and anonymity revokers (by default 10 of them).
It generates a public file with a list of all identity providers and for each of them a file with their private keys.
The public file must be available to the account holder so they can use the public keys to create the pre-identity object.
The private file must be available to the identity provider.
- `generate-global` generates a global context of parameters which need to be put on the chain (and are needed by the account holder to generate the credentials to deploy on the chain).
