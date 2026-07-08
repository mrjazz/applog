# AGENTS.md

## Project overview
A macOS productivity application that automatically measures desktop activity, provie to user detailed statistics

## Architecture
- Prefer MVVM for SwiftUI screens.
- Keep UI code in Views, state logic in ViewModels, and business logic in Services.
- Prefer value types (`struct`, `enum`) over classes unless reference semantics are required.
- Use dependency injection through initializers or environment values.
- Keep modules small and files focused on one responsibility.

## Project structure
- `applog/` - app source code
- `applog/Views/` - SwiftUI views
- `applog/ViewModels/` - observable state and UI logic
- `applog/Models/` - data models
- `applog/Services/` - networking, persistence, and domain logic
- `applog/Extensions/` - reusable extensions
- `applog/Resources/` - assets, strings, and other resources


## Swift style
- Follow Swift API Design Guidelines.
- Use `camelCase` for properties and methods, `PascalCase` for types.
- Prefer `async/await` over callbacks.
- Use `guard` for early exits.
- Handle optionals safely.
- Prefer strong typing and avoid unnecessary type erasure.
- Use `@Observable` for modern state management when supported by the deployment target.

## SwiftUI rules
- Prefer SwiftUI for new UI.
- Use AppKit only when SwiftUI cannot do the job.
- Keep views declarative and lightweight.
- Move side effects out of views.
- Use `@State`, `@Binding`, `@Environment`, and observation correctly.
- Keep previews up to date for all non-trivial views.

## macOS-specific rules
- Target macOS: [set your minimum version here].
- Document required entitlements and permissions.
- Note whether the app is sandboxed and how signing is handled.
- Use AppKit bridging only for features SwiftUI does not support.
- Avoid iOS-only APIs unless explicitly wrapped for macOS.

## Error handling
- Prefer domain-specific error enums.
- Use `throws` for recoverable failures.
- Use `Result` only when it improves API clarity.
- Provide user-facing error messages in a centralized way.

## Data and persistence
- Use SwiftData, Core Data, or file storage only where appropriate.
- Keep persistence logic isolated from views.
- Document schema or migration rules here if applicable.

## Testing
- Add unit tests for ViewModels and Services.
- Add UI tests for critical flows.
- When changing behavior, update or add tests.
- Prefer deterministic tests and avoid hidden dependencies.

## Working rules for Codex
- Before changing code, inspect nearby files and follow existing patterns.
- Do not introduce new frameworks unless necessary.
- Do not rename files, types, or directories without a strong reason.
- Prefer minimal, compile-safe changes.
- If unsure, ask for clarification instead of guessing.

## Self improvement

When you see the same request couple of times, propose to add it into AGENTS.md, Skill or Command.