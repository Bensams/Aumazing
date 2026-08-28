# Aumazing

## Vision

Aumazing is a gamified 2D mobile learning app for children aged 2-6 with early-stage Autism Spectrum Disorder (ASD). It uses AI-driven assessment, personalized learning modules, progress tracking, and a parent dashboard to support early intervention and home-based therapy in an engaging, child-friendly way.

## Tech Stack

- **Framework**: Flutter 3.7.2+
- **Platforms**: Android, iOS, Web, Desktop (Linux, macOS, Windows)
- **Architecture**: Feature-based modular architecture
- **Backend**: (To be determined - Firebase/Supabase)
- **AI/ML**: (To be determined - TensorFlow Lite/on-device)

## Project Structure

```
apps/
  ├── main_app/         # Main Flutter application
  └── game_lab/         # Game development/experimentation
packages/
  └── (shared packages)
```

## Current Status

- Basic Flutter app structure in place
- Multi-platform support configured
- Core directory structure established

## Milestones

### M1: Foundation & UI System
**Goal**: Establish core UI components and app shell

**Deliverables**:
- Design system (colors, typography, animations)
- Child-friendly UI components (large touch targets, simple layouts)
- Navigation structure
- Splash screen and onboarding flow
- Sound and haptic feedback system

### M2: Game Engine & Activities
**Goal**: Build 2D interactive activity framework

**Deliverables**:
- 2D game rendering engine
- Touch/gesture interaction system
- Activity templates (matching, sorting, tracing)
- Reward and animation system
- First set of learning activities

### M3: AI Assessment System
**Goal**: Implement adaptive learning assessment

**Deliverables**:
- Behavioral tracking during activities
- Skill level detection algorithms
- Progression decision engine
- On-device ML models (TensorFlow Lite)
- Privacy-compliant data collection

### M4: Personalization Engine
**Goal**: Create adaptive learning paths

**Deliverables**:
- User profile management
- Dynamic difficulty adjustment
- Personalized activity sequencing
- Interest-based content selection
- Learning pace adaptation

### M5: Progress Tracking & Analytics
**Goal**: Track and visualize child development

**Deliverables**:
- Local progress storage
- Skill milestone tracking
- Session analytics
- Development reports
- Data export capability

### M6: Parent Dashboard
**Goal**: Provide parents with insights and controls

**Deliverables**:
- Secure parent authentication
- Progress visualization (charts, timelines)
- Activity recommendations
- Parental controls and settings
- Share progress with therapists

### M7: Content Management
**Goal**: Enable content expansion and updates

**Deliverables**:
- Content delivery system
- Offline content caching
- New activity deployment
- Asset management
- Voice/audio content system

### M8: Deployment & Distribution
**Goal**: Prepare for production release

**Deliverables**:
- App store submissions (iOS/Android)
- Performance optimization
- Accessibility compliance
- Security audit
- Beta testing program

## Next Actions

1. **Immediate**: Complete M1 - establish UI system and design tokens
2. **Short-term**: Begin M2 - implement first learning activities
3. **Medium-term**: Integrate M3 AI assessment with M2 activities

## Notes

- Prioritize child safety and privacy (COPPA compliance)
- Design for limited attention spans (2-6 year olds)
- Ensure offline functionality for home therapy use
- Consider sensory sensitivities in design (calm colors, optional sounds)
