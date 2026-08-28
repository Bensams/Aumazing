# Aumazing AI Assessment

XGBoost-based developmental profile prediction API for the Aumazing app.

## Overview

This service analyzes children's gameplay session data from the Aumazing app to predict their developmental profile and recommend appropriate learning modules. It uses a trained XGBoost multi-class classifier to categorize children into one of 5 developmental profiles.

## Developmental Profiles

| Profile | Description | Recommended Modules | Skill Areas |
|---------|-------------|-------------------|-------------|
| `communication_support` | Needs help with imitation & verbal instructions | Copy Me, Do What I Say | Communication |
| `social_support` | Needs help with turn-taking & social interaction | My Turn, Your Turn | Social Interaction |
| `play_support` | Needs help with matching & creative play | Match It, Copy Me | Play Skills |
| `attention_support` | Needs help with focus & sustained attention | Do What I Say, Match It | Attention |
| `balanced_profile` | Balanced skills across all areas | All modules | All areas |

## Architecture

```
ai_assessment/
├── app/
│   ├── __init__.py          # Package version info
│   ├── config.py            # Environment configuration
│   ├── feature_aggregator.py # Transforms raw game data → 12 ML features
│   ├── main.py              # FastAPI application with 3 endpoints
│   ├── model_loader.py      # XGBoost model loading and prediction
│   ├── rules.py             # Business rules and module recommendations
│   ├── schemas.py           # Pydantic request/response schemas
│   └── supabase_client.py   # Supabase database client
├── models/
│   ├── feature_names.json   # 12 feature names for the model
│   ├── label_encoder.pkl    # Scikit-learn label encoder
│   └── xgboost_preassessment.pkl  # Trained XGBoost model
├── training/
│   ├── generate_training_data.py  # Synthetic data generator
│   ├── sample_preassessment_data.csv  # 200-row training dataset
│   └── train_model.py       # Model training with 5-fold CV
├── .env.example             # Environment variable template
├── requirements.txt         # Python dependencies
└── README.md                # This file
```

## API Endpoints

### 1. `POST /predict-preassessment`
Direct feature input — accepts the 12 pre-computed features.

**Request:**
```json
{
  "overall_accuracy": 0.35,
  "overall_avg_response_time": 6.5,
  "overall_task_completion_rate": 0.4,
  "overall_retry_count": 5,
  "overall_hint_count": 8,
  "overall_prompt_dependency_score": 0.6,
  "overall_idle_time_seconds": 20,
  "overall_invalid_touch_count": 7,
  "copy_me_accuracy": 0.25,
  "match_it_accuracy": 0.6,
  "my_turn_your_turn_accuracy": 0.55,
  "do_what_i_say_accuracy": 0.3
}
```

### 2. `POST /predict-from-sessions`
Raw game session input — computes features automatically from gameplay data.

**Request:**
```json
{
  "child_id": "uuid-here",
  "sessions": [
    {
      "game_id": "copy_me",
      "score": 3,
      "total_items": 10,
      "error_count": 4,
      "total_response_time_ms": 45000,
      "retry_count": 2,
      "hint_count": 5,
      "idle_time_seconds": 12.5,
      "random_touch_count": 3
    },
    {
      "game_id": "match_it",
      "score": 7,
      "total_items": 10,
      "error_count": 2,
      "total_response_time_ms": 30000
    }
  ]
}
```

### 3. `POST /predict-from-supabase`
Fetches game sessions directly from Supabase and optionally saves results back.

**Request:**
```json
{
  "child_id": "uuid-here",
  "assessment_run_id": "uuid-here",
  "save_results": true
}
```

### Response Format (all endpoints)
```json
{
  "predicted_profile": "communication_support",
  "confidence": 0.82,
  "pre_assessment_result": {
    "summary": "Your child may benefit from activities that build imitation and verbal instruction skills.",
    "support_level": "high"
  },
  "recommended_modules": ["Copy Me", "Do What I Say"],
  "feature_values": {
    "overall_accuracy": 0.35,
    "copy_me_accuracy": 0.25,
    "...": "..."
  }
}
```

## Setup

### Prerequisites
- Python 3.9+
- pip

### Installation
```bash
cd ai_assessment
pip install -r requirements.txt
```

### Configuration
```bash
cp .env.example .env
# Edit .env with your Supabase credentials (only needed for /predict-from-supabase)
```

### Running the API
```bash
cd ai_assessment
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API docs available at: http://localhost:8000/docs

## Training

### Regenerate Training Data
```bash
cd ai_assessment/training
python generate_training_data.py --samples-per-class 40 --output sample_preassessment_data.csv
```

### Retrain Model
```bash
cd ai_assessment/training
python train_model.py --data sample_preassessment_data.csv
```

Current model performance: **97.5% mean 5-fold CV accuracy**

## Integration with Flutter App

The Flutter app calls this API via the `/predict-from-sessions` endpoint after a child completes the pre-assessment games. The flow is:

1. Child plays 4 mini-games (Copy Me, Match It, My Turn Your Turn, Do What I Say)
2. App collects `GameplaySession` data for each game
3. App sends sessions to `POST /predict-from-sessions`
4. API computes 12 features, runs XGBoost prediction, returns profile + recommendations
5. App displays results and sets up recommended modules

## Supabase Integration

The API can optionally read/write to Supabase:
- **Read**: Fetch game sessions via `/predict-from-supabase`
- **Write**: Save `assessment_results` and `module_recommendations`

Required Supabase migration: `supabase/migrations/20260424_ai_assessment_columns.sql`

## Feature Mapping

| # | Feature | Source | Computation |
|---|---------|--------|-------------|
| 1 | `overall_accuracy` | `score / total_items` | Mean across all sessions |
| 2 | `overall_avg_response_time` | `total_response_time_ms` | Mean per-item time in seconds |
| 3 | `overall_task_completion_rate` | `score > 0` | Fraction of sessions with any score |
| 4 | `overall_retry_count` | `retry_count` | Mean across sessions |
| 5 | `overall_hint_count` | `hint_count` | Mean across sessions |
| 6 | `overall_prompt_dependency_score` | `hint_count / total_items` | Mean ratio across sessions |
| 7 | `overall_idle_time_seconds` | `idle_time_seconds` | Mean across sessions |
| 8 | `overall_invalid_touch_count` | `random_touch_count` | Mean across sessions |
| 9 | `copy_me_accuracy` | Copy Me sessions | Mean accuracy (default 0.5) |
| 10 | `match_it_accuracy` | Match It sessions | Mean accuracy (default 0.5) |
| 11 | `my_turn_your_turn_accuracy` | My Turn Your Turn sessions | Mean accuracy (default 0.5) |
| 12 | `do_what_i_say_accuracy` | Do What I Say sessions | Mean accuracy (default 0.5) |
