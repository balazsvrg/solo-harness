# Language-agnostic core with stack overlays

The template must serve future projects in any language, and one stack baked in would be dead weight or wrong for most of them. So the core holds only the process and the gates. Stack-specific parts (the `check-app` and `fmt` targets, Dependabot ecosystems, the release-please release type) are filled later by an overlay or by the project. The cost: a new project's `make check` fails as soon as app source exists, until someone configures `check-app`. Bootstrap prints a "configure `check-app`" notice to make that step hard to miss.
