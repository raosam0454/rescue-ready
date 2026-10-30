# Rescue Ready

Rescue Ready is an offline-first iOS app for volunteer team leads at small community food rescue groups. It tracks surplus food from an event pickup through a safety check to a drop point handover, so every batch stays out of the temperature danger zone and inside its safe hold time.

## Features

| Area | What it does |
|------|--------------|
| Events and pickups | Create an event, then log pickups and food batches (weight, allergens) against it |
| Safety check | Record a batch temperature and allergen declaration. Readings between 5°C and 60°C fail the check |
| Hold window | Each batch has a 4-hour safe hold window, starting when it is picked up |
| Handover and discard | Hand a batch over to a drop point, or discard it with a required reason |
| Impact | See kilograms rescued, an estimated meal count, and batches handed over or discarded |
| Expiry alerts | A local notification 15 minutes before a batch's hold window ends |
| Home screen widget | Lists open batches by soonest expiry and flags those under 30 minutes |

All data is stored on the device. The app does not need a network connection or an account.

## Requirements

- Xcode 26 or later
- iOS 17.0 or later (Simulator or device)
- No third-party dependencies. The app uses only Apple frameworks: SwiftUI, Core Data, WidgetKit, UserNotifications and Swift Testing

## Getting started

1. Clone the repository:
   ```bash
   git clone https://github.com/raosam0454/rescue-ready.git
   ```
2. Open `rescue-ready.xcodeproj` in Xcode.
3. Select the `rescue-ready` scheme and an iPhone Simulator.
4. Press **Cmd+R** to build and run.

Debug builds seed sample events, volunteers and drop points on first launch, so the app has data to explore straight away. Release builds seed only the volunteer and drop points the app needs to work.

To run the app on a physical device, change the signing team and the App Group (`group.sam.rao.au.rescue-ready`) in both the app and widget targets to ones your Apple developer account owns.

## Running the tests

Select the `rescue-ready` scheme and press **Cmd+U**. This runs:

- **Unit tests** (`rescue-readyTests`, Swift Testing): use cases, view models and Core Data repositories
- **UI tests** (`rescue-readyUITests`, XCTest): navigation smoke tests across the main tabs

## Architecture

The app follows MVVM with a use case layer and the repository pattern.

```
 SwiftUI View
      |
      v
 ViewModel (@Observable, @MainActor)
      |
      v
 Use Case (one business action, e.g. RecordSafetyCheck)
      |
      v
 Repository protocol (Domain)
      |
      +--> Core Data repository (app)
      +--> In-memory repository (tests and previews)
```

- **Views** render state and forward user actions. They hold no business logic.
- **ViewModels** call use cases and turn results and errors into view state.
- **Use cases** hold the business rules (danger zone, hold window, allergen declaration). They take an injected clock so time-based rules can be tested.
- **Repositories** hide storage behind protocols. Core Data work runs on background contexts.
- **AppContainer** is the composition root that wires everything together.

## Project structure

```
rescue-ready/
├── App/                  App entry point, AppContainer, root navigation
├── Domain/
│   ├── Models/           Event, Pickup, FoodBatch, SafetyCheck, DropPoint, value types
│   ├── UseCases/         One file per business action
│   ├── Repositories/     Repository protocols
│   └── Errors/           DomainError
├── Data/
│   ├── CoreData/         Persistence stack, data model, mapping, seeder
│   ├── Repositories/     Core Data repository implementations
│   └── InMemory/         In-memory repositories for tests and previews
├── Platform/
│   └── Notifications/    Local notification scheduler
├── Presentation/         Screens and view models, grouped by feature, plus a shared design system
└── Resources/            Assets and privacy manifest
RescueReadyWidget/        Home screen widget extension
rescue-readyTests/        Unit tests
rescue-readyUITests/      UI tests
tools/                    Script that frames screenshots for the App Store
```

## Branching

- `main` holds released code
- `develop` is the integration branch
- Work happens on `feat/`, `fix/` and `chore/` branches, merged into `develop` through pull requests
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
