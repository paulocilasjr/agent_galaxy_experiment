# Claude Multimodal Steps Plan
## Predicting Patient Recurrence using Multimodal Dataset from Zenodo

**Created:** 2026-02-10
**Objective:** Build a model to predict patient recurrence using multimodal data (images + tabular) from the HANCOCK TMA dataset
**Galaxy API:** https://usegalaxy.org
**Primary Tool:** Multimodal Learner 0.1.5 (toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner)

---

## Dataset Overview

### Source URLs (Zenodo)
1. **Training data:** https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv
2. **Testing data:** https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv
3. **Images:** https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip

### Data Description
- **TMA Cores:** Tissue Microarray images with CD3 and CD8 immunohistochemistry staining
- **Tabular Data:** Patient clinical/molecular data with image path references
- **Target Variable:** Patient recurrence (binary classification)
- **Modalities:** Images (histopathology) + Tabular (clinical features)

---

## Step-by-Step Implementation Plan

### Phase 1: Environment Setup & Verification

#### Step 1.1: Verify Galaxy API Connectivity
- Test connection to usegalaxy.org using API key
- Verify user authentication
- Check API access permissions

**Script:** `01_verify_galaxy_connection.sh`
```bash
curl -H "x-api-key: $GALAXY_API_KEY" \
  https://usegalaxy.org/api/users/current
```

#### Step 1.2: Install Required Python Dependencies
- Install bioblend (Galaxy Python SDK)
- Install supporting libraries (requests, pyyaml, pandas)

**Note:** Use virtual environment to avoid system package conflicts
```bash
python3 -m venv venv_multimodal
source venv_multimodal/bin/activate
pip install bioblend requests pyyaml pandas
```

---

### Phase 2: Galaxy History & Data Upload

#### Step 2.1: Create Galaxy History
- Create a new history named: `Claude-Multimodal-Recurrence-Prediction`
- Record history ID for subsequent operations

**API Endpoint:** `POST /api/histories`
**Expected Output:** History ID (e.g., `bbd44e69cb8906b5ce223e9a81174ae0`)

#### Step 2.2: Upload Datasets via URL Fetch
Upload all three datasets from Zenodo using Galaxy's URL fetch tool:

1. **HANCOCK_train_split.csv**
   - URL: https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv
   - File type: `csv`
   - Expected columns: `patient_id`, clinical features, `CD3_image_path`, `CD8_image_path`, `target`

2. **HANCOCK_test_split.csv**
   - URL: https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv
   - File type: `csv`
   - Same schema as training data

3. **tma_cores_cd3_cd8_images.zip**
   - URL: https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip
   - File type: `zip` (auto-decompress: false)
   - Contains: TMA core images referenced by CSV paths

**API Endpoint:** `POST /api/tools`
**Tool ID:** `upload1` or `__FETCH_FROM_URL__`

**Expected Payload Structure:**
```json
{
  "tool_id": "__FETCH_FROM_URL__",
  "history_id": "<history_id>",
  "inputs": {
    "targets": [
      {
        "destination": {
          "type": "hdas"
        },
        "elements_from": "url",
        "src": "url",
        "url": "https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv",
        "ext": "csv",
        "space_to_tab": false
      },
      {
        "destination": {
          "type": "hdas"
        },
        "elements_from": "url",
        "src": "url",
        "url": "https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv",
        "ext": "csv",
        "space_to_tab": false
      },
      {
        "destination": {
          "type": "hdas"
        },
        "elements_from": "url",
        "src": "url",
        "url": "https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip",
        "ext": "zip",
        "auto_decompress": false
      }
    ]
  }
}
```

#### Step 2.3: Monitor Upload Status
- Poll dataset status until all reach `ok` state
- Handle potential errors (network timeouts, file format issues)
- Record dataset IDs for downstream tool execution

**Polling Strategy:**
- Initial delay: 5 seconds
- Poll interval: 10 seconds
- Maximum attempts: 60 (10 minutes timeout)

**API Endpoint:** `GET /api/datasets/{dataset_id}`

---

### Phase 3: Data Inspection & Validation

#### Step 3.1: Download and Inspect CSV Schema
- Download first 100 rows of training CSV
- Identify column indices:
  - Target column (typically `target` or `recurrence`)
  - Patient ID column (for leakage prevention)
  - Image path columns (`CD3_image_path`, `CD8_image_path`)
  - Feature columns (categorical, numerical)

**Expected Schema:**
```
Column 0: patient_id (identifier)
Column 1-N: Clinical/molecular features
Column N+1: CD3_image_path
Column N+2: CD8_image_path
Column N+3: target (0 = no recurrence, 1 = recurrence)
```

#### Step 3.2: Validate Image ZIP Contents
- Confirm ZIP contains images matching CSV paths
- Check image format (PNG, JPG, TIFF)
- Verify image accessibility

---

### Phase 4: Multimodal Learner Configuration

#### Step 4.1: Retrieve Tool Schema
**Tool ID:** `toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5`

**API Endpoint:** `GET /api/tools/{tool_id}/build`

This provides:
- Input parameter definitions
- Conditional parameter structures
- Valid enum values
- Default configurations

#### Step 4.2: Configure Training Parameters

**Core Configuration:**
```yaml
# Dataset Configuration
training_dataset_id: <train_csv_dataset_id>
test_dataset_id: <test_csv_dataset_id>  # Separate test set
target_column: <column_index>  # e.g., 3
sample_id_column: <column_index>  # e.g., 1 (patient_id for leakage prevention)

# Image Modality
image_modality:
  enabled: true
  image_zip_dataset_id: <zip_dataset_id>
  image_columns:
    - <CD3_image_path_column_index>
    - <CD8_image_path_column_index>

# Model Configuration
model:
  names:
    - timm_image  # For image processing
    - ft_transformer  # For tabular features
    - fusion_mlp  # For multimodal fusion

  timm_image:
    checkpoint_name: "caformer_b36.sail_in22k_ft_in1k_384"
    # Strong vision transformer backbone
    train_transforms:
      - resize_shorter_side
      - center_crop
      - trivial_augment
    image_size: 384

  ft_transformer:
    data_types:
      - categorical
      - numerical
    token_dim: 192
    num_blocks: 3

  fusion_mlp:
    hidden_sizes: [128]
    activation: leaky_relu
    dropout: 0.1

# Optimization
optim:
  optim_type: adamw
  lr: 0.0001
  weight_decay: 0.001
  max_epochs: 20
  batch_size: 128
  patience: 10  # Early stopping
  val_check_interval: 0.5

# Environment
env:
  num_gpus: 1  # CRITICAL: Single GPU to avoid distributed training errors
  precision: "16-mixed"  # Mixed precision for efficiency
  seed: 42

# Evaluation
eval_metric: roc_auc  # Primary metric for binary classification
```

**Quality Presets:**
- `preset: best_quality` (recommended for production models)
- Alternative: `medium_quality` (faster for testing)

#### Step 4.3: Address Common Configuration Pitfalls

**Known Issues & Solutions:**
1. **Multi-GPU Errors:** Always set `num_gpus: 1` to avoid NCCL distributed training errors
2. **Conditional Parameters:** Flatten nested conditional structures in API payload
3. **Image Path Handling:** Ensure ZIP structure matches CSV path references exactly
4. **Memory Management:** Adjust batch size based on image resolution and GPU memory

---

### Phase 5: Model Training Execution

#### Step 5.1: Submit Training Job
**API Endpoint:** `POST /api/tools`

Submit the configured Multimodal Learner tool with all parameters.

**Expected Outputs:**
1. **Training Report (HTML):** Comprehensive training metrics, visualizations
2. **Training Config (YAML):** Full hyperparameter configuration used
3. **Metric Results (JSON):** Structured evaluation metrics
4. **Trained Model (ZIP):** Serialized model weights (if enabled)

#### Step 5.2: Monitor Job Execution
- Poll job status until terminal state (`ok`, `error`, or `paused`)
- Log intermediate states for debugging
- Capture stdout/stderr if job fails

**Polling Strategy:**
- Initial delay: 30 seconds (preprocessing phase)
- Poll interval: 60 seconds
- Maximum runtime: 7200 seconds (2 hours)

**API Endpoint:** `GET /api/jobs/{job_id}`

**Terminal States:**
- `ok`: Training completed successfully
- `error`: Job failed (inspect stderr for details)
- `paused`: Job paused by user/system

#### Step 5.3: Handle Training Failures
Common failure modes:
1. **CUDA/GPU Errors:** Reduce batch size, disable mixed precision
2. **Out of Memory:** Decrease batch size, reduce model size
3. **Data Format Errors:** Validate CSV schema, image paths
4. **Timeout:** Increase time limit or reduce max_epochs

---

### Phase 6: Results Download & Evaluation

#### Step 6.1: Download All Output Files
Create local directory structure:
```
experiments/exp_claude_multimodal_dataset/
├── outputs/
│   ├── multimodal_report.html
│   ├── multimodal_training_config.yaml
│   ├── multimodal_metric_results.json
│   └── trained_model.zip (if available)
```

**API Endpoint:** `GET /api/datasets/{dataset_id}/download`

#### Step 6.2: Extract and Parse Metrics
From `multimodal_metric_results.json`:
```json
{
  "test_roc_auc": 0.XXX,
  "test_accuracy": 0.XXX,
  "test_precision": 0.XXX,
  "test_recall": 0.XXX,
  "test_f1_score": 0.XXX,
  "validation_roc_auc": 0.XXX
}
```

Primary metric: **ROC-AUC** (Area Under Receiver Operating Characteristic curve)
- Target: > 0.75 (good clinical utility)
- Excellent: > 0.85
- Outstanding: > 0.90

#### Step 6.3: Analyze Training Report
The HTML report contains:
- Training/validation loss curves
- ROC curves for test set
- Confusion matrix
- Feature importance (if available)
- Model architecture summary

#### Step 6.4: Generate Summary Document
Create `evaluation_summary.md` with:
- Final metrics table
- Comparison to baseline (if available)
- Identified strengths/weaknesses
- Recommendations for improvement

---

### Phase 7: Model Iteration & Improvement

#### Step 7.1: Hyperparameter Tuning Strategy
If initial ROC-AUC is suboptimal, iterate on:

**Learning Rate:**
- Try: 0.0001, 0.0005, 0.001
- Use learning rate schedulers (cosine decay)

**Model Architecture:**
- Stronger image backbone: `convnext_base`, `swin_base_patch4_window7_224`
- Deeper fusion MLP: `[256, 128, 64]`

**Data Augmentation:**
- Enable mixup/cutmix for images
- Adjust augmentation strength

**Regularization:**
- Increase dropout: 0.1 → 0.2, 0.3
- Adjust weight decay: 0.001 → 0.01

**Training Duration:**
- Increase max_epochs: 20 → 30, 40
- Longer time_limit: 7200 → 10800

#### Step 7.2: Ensemble Methods
For production deployment:
- Train multiple models with different random seeds
- Average predictions (model soup approach)
- Use top-k checkpoint averaging

#### Step 7.3: Cross-Validation (Advanced)
- Implement k-fold cross-validation
- Requires custom workflow in Galaxy
- Provides more robust performance estimates

---

## Phase 8: Model Deployment & Export

#### Step 8.1: Download Trained Model
If model export is enabled, download the serialized model:
- Format: ZIP archive with PyTorch checkpoints
- Contains: Model weights, tokenizers, preprocessors

#### Step 8.2: Local Inference Testing
Test model on local data:
```python
from multimodal_learner import MultimodalPredictor

predictor = MultimodalPredictor.load("trained_model.zip")
predictions = predictor.predict(test_data)
```

#### Step 8.3: Documentation
Create deployment documentation:
- Model card (architecture, performance, limitations)
- Inference API specification
- Input data requirements
- Expected prediction format

---

## Success Criteria

### Minimum Viable Model
- ✅ Training completes without errors
- ✅ Test ROC-AUC > 0.65
- ✅ Model generalizes (no overfitting)

### Production-Ready Model
- ✅ Test ROC-AUC > 0.75
- ✅ Calibrated predictions (reliability diagram)
- ✅ Robust to missing data
- ✅ Inference time < 1 second per patient

### Research-Grade Model
- ✅ Test ROC-AUC > 0.85
- ✅ Interpretable feature importance
- ✅ Cross-validated performance
- ✅ Comparison to clinical baselines

---

## Timeline Estimate

**Phase 1-2 (Setup & Upload):** 15-30 minutes
**Phase 3 (Validation):** 10-15 minutes
**Phase 4 (Configuration):** 20-30 minutes
**Phase 5 (Training):** 30-120 minutes (depends on dataset size)
**Phase 6 (Evaluation):** 15-20 minutes
**Phase 7 (Iteration):** Variable (1-5 iterations)

**Total (Single Run):** ~2-4 hours
**Total (With Iterations):** 4-12 hours

---

## Key References

### Galaxy Resources
- **Galaxy ML Community:** https://galaxyproject.org/community/machine-learning/
- **Galaxy ML Tools:** https://ml.usegalaxy.eu
- **Training Materials:** https://training.galaxyproject.org
- **Tool Repository:** https://github.com/bgruening/galaxytools, https://github.com/goeckslab/Galaxy-ML

### Scientific Background
- **Galaxy-ML Paper:** [PLOS Computational Biology](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009014)
- **Multimodal Learning Review:** Medical imaging + clinical data integration
- **AutoML for Multimodal Data:** AutoGluon, AutoKeras frameworks

### Previous Experiment Reference
- **Experiment ID:** `exp_multimodal_dataset__ds_hancock_tma__tool_multimodal`
- **Run ID:** `run_20260208_232320Z_setup`
- **Location:** `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/`
- **Key Learnings:**
  - Single GPU configuration prevents distributed training errors
  - CAFormer B36 backbone provides strong image representations
  - ROC-AUC metric appropriate for imbalanced recurrence prediction
  - Typical training time: 30-90 minutes with early stopping

---

## Risk Mitigation

### Technical Risks
1. **GPU Availability:** usegalaxy.org has limited GPU resources
   - Mitigation: Submit jobs during off-peak hours
   - Alternative: Use usegalaxy.eu (often has more capacity)

2. **Dataset Size:** Large image archives may timeout during upload
   - Mitigation: Monitor upload progress, restart if needed
   - Alternative: Upload to Galaxy data library first

3. **Model Complexity:** Large models may exceed memory limits
   - Mitigation: Start with smaller architectures, scale up iteratively
   - Alternative: Use model quantization, mixed precision

### Scientific Risks
1. **Class Imbalance:** Recurrence may be rare event
   - Mitigation: Use ROC-AUC (handles imbalance), class weights
   - Alternative: Focal loss, oversampling techniques

2. **Data Leakage:** Multiple samples from same patient
   - Mitigation: Use patient_id for sample_id_column
   - Validation: Check patient overlap between train/test

3. **Image Quality:** TMA cores may have artifacts, staining variability
   - Mitigation: Strong augmentation, robust normalization
   - Alternative: Preprocessing pipeline for quality filtering

---

## Next Steps After Initial Model

1. **Clinical Validation:**
   - Collaborate with domain experts
   - Validate predictions on independent cohort
   - Assess clinical utility and actionability

2. **Explainability:**
   - Generate attention maps for image predictions
   - SHAP values for tabular features
   - Case studies of high-confidence predictions

3. **Deployment:**
   - REST API for inference
   - Integration with clinical systems
   - Continuous monitoring and retraining pipeline

---

## Appendix: Tool Comparison

### Why Multimodal Learner over Alternatives?

| Tool | Strengths | Limitations | Use Case Fit |
|------|-----------|-------------|--------------|
| **Multimodal Learner 0.1.5** | Native image+tabular, AutoML, GPU-accelerated | Limited customization | ✅ **Best fit** |
| Image Learner | Strong CNN support | No tabular integration | ❌ Images only |
| Keras Sequential | Fully customizable | Requires manual feature engineering | ⚠️ Complex setup |
| scikit-learn | Fast, interpretable | No deep learning for images | ❌ Tabular only |

**Verdict:** Multimodal Learner is purpose-built for this exact use case.

---

**Document Version:** 1.0
**Last Updated:** 2026-02-10
**Author:** Claude (Anthropic)
**Experiment ID:** exp_claude_multimodal_dataset
