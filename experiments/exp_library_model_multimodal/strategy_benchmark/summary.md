# Multimodal Strategy Benchmark

| strategy            | model                      | model_strategy   |   train_roc_auc |   test_roc_auc |   train_pr_auc |   test_pr_auc |   text_features |   total_features |
|:--------------------|:---------------------------|:-----------------|----------------:|---------------:|---------------:|--------------:|----------------:|-----------------:|
| stack_char35_et1500 | StackedExtraTreesTextLR    | stacked_et_text  |        0.671598 |       0.792679 |       0.528758 |      0.689498 |            3645 |             3752 |
| stack_word12_et1500 | StackedExtraTreesTextLR    | stacked_et_text  |        0.665393 |       0.791779 |       0.524527 |      0.68323  |             757 |              864 |
| tri_logistic        | LogisticRegressionTriModal | tri_logistic     |        0.91077  |       0.769577 |       0.787615 |      0.594789 |             757 |              864 |

Target: test ROC-AUC >= 0.79