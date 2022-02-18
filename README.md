# About kyoko-ccal

- what's ccal

    full name <b>Cross-Chain Asset Lending</b>.

- how it works
    asset holder deposit asset on Polygon、BSC、Ethereum and etc,
    borrower can freeze token for specified asset on Polygon. if
    the asset is pledged on Polygon, borrower can get assets directly.
    otherwise, borrower can call our service api to get asset on target chain.

- basic logic
  * freeze token, withdraw token and withdraw interest is occur on <b>main-chain(Polygon)</b>.
  
  * depositor set daily price, minimum pay amount，borrow cycle and totalAmount. totalAmount include the value of the asset.

  * how can i withdraw my freeze-token after repay asset?
    - call our service via api request.
    - service call contract's method <b>withdrawFreezeTokenViaBot</b>.
    - contract transfer token to your wallet.

  * how can i get erc721 asset after freeze token?
    - call our service via api request.
    - service call contract's method <b>borrowAssetViaBot</b>.
    - after check, contract transfer asset to your wallet.

- works flow

    * deposit、borrow asset and freeze token on same chain(Polygon)
        - depositAsset
        - freezeTokenForMainChainAsset
        - repayAsset
        - withdrawFreezeTokenViaBot(borrower)
        - withdrawToolInterest(depositor)

    * freeze token on main-chain(Polygon), deposit、borrow asset on other chain
        - depositAsset (BSC)
        - freezeTokenForOtherChainAsset(Polygon)
            * FreezeToken event(dispatch Event on Polygon)
        - borrowAssetViaBot(BSC)
        - repayAsset(BSC)
            - RepayAsset event(dispatch Event on BSC)
        - syncInterestAfterRepayViaBot(Polygon, trigger by bot call)
        - withdrawFrozenToken(borrower)
        - withdrawToolInterest(depositor)

    * about liquidate
      - Only depositor can trigger liquidation after borrow-relationship is expired
      - After liquidation, the depositor can get all the tokens that the borrower has frozen for the asset. borrower get the asset.
      - if depositor isn't withdraw asset, liquidation will not happen even though is borrow-relationship is expired.
