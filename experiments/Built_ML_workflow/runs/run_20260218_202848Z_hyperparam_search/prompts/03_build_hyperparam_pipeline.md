Build a Pipeline Builder-based ML chain with hyperparameter search:
1) Build estimator with Pipeline Builder.
2) Run SearchCV on Chowell_train_Response with selected parameter grid.
3) Predict on Chowell_test_No_Response and MSK1_No_Response using tuned model.
4) Plot confusion matrices against corresponding *_Response tables.
5) Extract executed chain as reusable workflow.
