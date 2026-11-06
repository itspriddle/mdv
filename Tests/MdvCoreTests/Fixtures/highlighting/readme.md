# Widget

A small library for building widgets, used by `HighlightingBenchmarkTests` as a typical README:
prose plus a dozen fenced code blocks in common languages.

## Installation

```sh
brew install widget
git clone https://github.com/example/widget.git
cd widget && make install PREFIX="$HOME/.local"
```

Or add it to `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/example/widget.git", from: "2.1.0"),
    ],
    targets: [
        .executableTarget(name: "App", dependencies: [.product(name: "Widget", package: "widget")]),
    ]
)
```

## Usage

```swift
import Widget

struct Greeter: Widget {
    let name: String
    var count = 0

    func render(into context: inout RenderContext) throws {
        guard !name.isEmpty else { throw WidgetError.missingName }
        context.write("Hello, \(name)! <b>\(count)</b> & more")
        for index in 0..<count where index.isMultiple(of: 2) {
            context.write("#\(index)")
        }
    }
}

@main
enum Main {
    static func main() async throws {
        let greeter = Greeter(name: "World", count: 3)
        try await Renderer.shared.render(greeter)
    }
}
```

From JavaScript:

```js
import { render } from "@example/widget";

export async function main(options = {}) {
  const items = await fetch("/api/items").then((response) => response.json());
  for (const item of items.filter((x) => x.enabled && x.count > 0)) {
    console.log(`Rendering ${item.name}…`, render(item, { ...options, strict: true }));
  }
  return items.length;
}
```

```typescript
interface Options {
  strict?: boolean;
  theme: "light" | "dark";
}

export class Widget<T extends object> {
  constructor(private readonly value: T, public options: Options = { theme: "light" }) {}
  map<U extends object>(transform: (value: T) => U): Widget<U> {
    return new Widget(transform(this.value), this.options);
  }
}
```

```python
from dataclasses import dataclass


@dataclass
class Widget:
    name: str
    count: int = 0

    def render(self) -> str:
        """Return the widget as HTML."""
        return f"<p>{self.name}: {self.count}</p>"


if __name__ == "__main__":
    print(Widget("demo", 3).render())
```

## Configuration

```json
{
  "name": "widget",
  "version": "2.1.0",
  "features": ["highlighting", "themes"],
  "limits": { "maxSize": 131072, "timeout": 1.5, "strict": true, "parent": null }
}
```

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: make test # runs everything
```

```toml
[widget]
theme = "dark"
max-size = 131_072
```

## Changes

```diff
diff --git a/Sources/Widget.swift b/Sources/Widget.swift
@@ -1,4 +1,4 @@
-let limit = 64
+let limit = 128
 let name = "widget"
```

```ruby
class Widget
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def to_s = "Widget(#{name})"
end
```

```go
package main

import "fmt"

func main() {
	for i := 0; i < 3; i++ {
		fmt.Printf("widget %d\n", i)
	}
}
```

```rust
fn main() {
    let widgets: Vec<String> = (0..3).map(|i| format!("widget {i}")).collect();
    println!("{widgets:?}");
}
```

## License

MIT
