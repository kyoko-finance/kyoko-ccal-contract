# About kyoko-ccal

- what's ccal

    full name <b>Cross-Chain Asset Lending</b>.

- how it works
    asset holder lend asset on BSC(main-chain), Ethereum, Polygon and etc,
    borrower can freeze token for specified asset on BSC. if
    the asset is pledged on BSC, borrower can get assets directly.
    If the asset is pledged on other chain, we use the [LayerZero](https://layerzero.network/)
    to transfer requests to complete the user's operation in the other chain.

- basic logic

  * CCALMainChain.sol deploy to main-chain, CCALSubChain.sol deploy to other chain.
  
  * deposit(): lender set daily price, minimum pay amount，currency token, borrow cycle and totalAmount, and lend the asset to ccal. totalAmount include the value of the asset.
  
  * editDepositAsset(): lender update the params

  * borrowAsset(): borrow the asset which is also lent on the main-chain

  * borrowOtherChainAsset(): borrow the asset which is lent on the other chain on the main-chain

  * repayAsset(): repay the asset on its location chain

  * withdrawAsset(): draw the asset or liquidate the frozen token on its location chain
  
  * withdrawToken(): draw the frozen token or earned rent on the main-chin

- works flow

    * lend, borrow and repay asset on main-chain
        - lender: deposit
        - borrower: borrowAsset
        - borrower: repayAsset
        - borrower: withdrawToken (draw the frozen token)
        - lender: withdrawToken (draw the earned rent)
        - lender: withdrawAsset

    * lend, repay asset on the other chain, borrow on the main-chin
        - lender: deposit
        - borrower: borrowOtherChainAsset (on main-chain)
        - borrower: repayAsset
        - borrower: withdrawToken  (on main-chain)
        - lender: withdrawToken  (on main-chain)
        - lender: withdrawAsset

    * about liquidate
      - Only lender can trigger liquidation after borrow-relationship is expired
      - After liquidation, the lender can get all the tokens that the borrower has frozen for the asset. borrower get the asset.
      - if lender don't withdraw asset, liquidation will not happen even though borrow-relationship is expired.
