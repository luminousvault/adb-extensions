# Contributing to ADB Extensions Kit

Thank you for your interest in contributing to ADB Extensions Kit (ak)! This document provides guidelines and information for contributors.

## Welcome

We welcome contributions of all kinds:
- Bug fixes
- New features
- Documentation improvements
- Code quality improvements
- Test coverage

## Getting Started

### Prerequisites

Before you begin development, ensure you have the following tools installed:

- **adb** (Android Debug Bridge) - Required for all ADB operations
- **aapt** (Android Asset Packaging Tool) - Required for the install command
- **apksigner** (requires ANDROID_HOME) - Required for the signature command
- **shc** (optional) - For compiling shell scripts to binary

### Development Setup

1. Fork and clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/adb-extensions.git
cd adb-extensions
```

2. Test the development version directly:

```bash
# No build needed for testing
./src/ak --version
./src/ak devices
```

## Project Structure

Understanding the project structure will help you navigate the codebase:

```
adb-extensions/
├── src/                        # Source code (modular)
│   ├── ak                      # Main entry point
│   ├── lib/
│   │   ├── common.sh          # Common utilities
│   │   ├── ui.sh              # Interactive UI
│   │   ├── device.sh          # Device management
│   │   └── commands/          # Command modules
│   │       ├── install.sh     # Install command
│   │       ├── pull.sh
│   │       ├── extract.sh
│   │       ├── info.sh
│   │       ├── permissions.sh
│   │       ├── uninstall.sh
│   │       ├── clear.sh
│   │       ├── kill.sh
│   │       ├── launch.sh
│   │       ├── signature.sh
│   │       ├── activities.sh
│   │       └── devices.sh
│   ├── completions/
│   │   └── _ak               # Zsh completion
│   └── VERSION
│
├── build/                     # Build output (generated)
│   ├── ak                     # Merged shell script
│   └── completions/
│
├── build.sh                   # Build system
├── ak.rb                      # Homebrew formula
├── README.md
└── CONTRIBUTING.md
```

### Key Components

- **`src/ak`**: Main entry point that sources library files and routes commands
- **`src/lib/common.sh`**: Shared utility functions (colors, error handling, etc.)
- **`src/lib/ui.sh`**: Interactive UI components (selection menus, keyboard input)
- **`src/lib/device.sh`**: Device detection and selection logic
- **`src/lib/commands/`**: Each command is a separate module with its own file

## Development Workflow

Follow this workflow when making changes:

```bash
# 1. Create a feature branch
git checkout -b feature/your-feature-name

# 2. Edit source files
vim src/lib/commands/pull.sh

# 3. Test directly (no build needed)
./src/ak extract com.example

# 4. Build to test the merged output
./build.sh

# 5. Test build output
./build/ak extract com.example

# 6. Install for system-wide testing (optional)
sudo ./build.sh --install

# 7. Verify installation
ak --version
ak extract com.example

# 8. Commit your changes
git add src/lib/commands/pull.sh
git commit -m "feat: improve pull command"

# 9. Push to your fork
git push origin feature/your-feature-name

# 10. Open a Pull Request
```

## Build System

The build system merges all modular source files into a single distributable script.

### Build Commands

```bash
# Build shell script
./build.sh

# Install locally (requires sudo)
sudo ./build.sh --install

# Uninstall
sudo ./build.sh --uninstall

# Clean build directory
./build.sh --clean

# Show help
./build.sh --help
```

### Build Output

- `build/ak` - Merged shell script (portable, ready to distribute)
- `build/completions/_ak` - Zsh completion file

### Module System

The project uses special markers for the build system:

#### Header Markers

```bash
#@@HEADER_START
# Command: extract
# Description: Extract APK from device
#@@HEADER_END
```

These markers are used to extract metadata for documentation generation.

#### Build Exclusion

```bash
#@@BUILD_EXCLUDE_START
# This code only runs in development
# It will be removed in the build output
#@@BUILD_EXCLUDE_END
```

Use this to exclude development-only code from the final build.

#### How It Works

1. The build system reads all source files from `src/`
2. It processes special markers (`#@@HEADER_START`, `#@@BUILD_EXCLUDE_START`, etc.)
3. All modules are merged into a single file `build/ak`
4. Optionally compiles to binary using shc

## Adding a New Command

To add a new command, follow these steps:

### 1. Create the Command File

Create a new file in `src/lib/commands/`:

```bash
touch src/lib/commands/mycommand.sh
```

### 2. Command Template

Use this template for your command:

```bash
#!/bin/bash
#@@BUILD_EXCLUDE_START
# ═══════════════════════════════════════════════════
# MY_COMMAND Command
# Description of what this command does
# ═══════════════════════════════════════════════════
#@@BUILD_EXCLUDE_END

# Completion definition: command name and description
: <<'AK_COMPLETION_DESC'
mycommand:Brief description for completion
AK_COMPLETION_DESC

# Completion handler: zsh completion code
: <<'AK_COMPLETION'
        mycommand)
          _arguments \
            '(- *)'{-h,--help}'[Show help for this command]' \
            '1:argument:_message "description"'
          ;;
AK_COMPLETION

show_help_mycommand() {
    echo -e "${CYAN}${BOLD}Usage:${NC} ak mycommand [-h|--help] [arguments...]"
    echo
    echo "Description: Detailed description of the command."
    echo
    echo "Options:"
    echo "  -h, --help  Show this help message"
    echo
    exit 1
}

cmd_mycommand() {
    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help_mycommand
                ;;
            -*)
                echo -e "${ERROR} Invalid option: $1"
                echo "Try 'ak mycommand --help' for more information."
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Select device
    find_and_select_device
    
    # Your command logic here
    echo "Executing mycommand..."
}
```

### 3. Update Main Entry Point

The build system automatically includes your command, but you should test it:

```bash
./src/ak mycommand
```

### 4. Add Documentation

Update README.md with your command's usage and examples.

## Code Style

Follow these guidelines for consistent code:

### Shell Script Style

- Use 4 spaces for indentation (no tabs)
- Use `snake_case` for function names
- Use `UPPER_CASE` for global constants
- Use `local` for function-scoped variables
- Always quote variables: `"$variable"`
- Use `[[ ]]` for conditionals instead of `[ ]`

### Function Names

- Commands: `cmd_commandname()`
- Help functions: `show_help_commandname()`
- Utility functions: `descriptive_name()`

### Error Handling

Always check command results and provide meaningful errors:

```bash
if ! adb shell "command"; then
    echo -e "${ERROR} Failed to execute command"
    exit 1
fi
```

### Color Variables

Use predefined color variables from `common.sh`:

- `${CYAN}` - Info messages
- `${GREEN}` - Success messages
- `${YELLOW}` - Warning messages
- `${RED}` - Error messages
- `${NC}` - No color (reset)
- `${BOLD}` - Bold text

## Testing

### Debug Mode

The project includes a comprehensive debug logging system for troubleshooting:

#### Enable Debug Mode

```bash
# Enable debug logging for any command
AK_DEBUG=1 ak <command> [options]

# Examples
AK_DEBUG=1 ak install ~/Downloads/app.apk
AK_DEBUG=1 ak devices
AK_DEBUG=1 ak extract com.example.app

# Debug logs are written to build/debug.log
cat build/debug.log

# Real-time monitoring
tail -f build/debug.log
```

#### Debug Log Format

```
[2025-12-30 09:07:29.123] [ui.sh:755] apply_filter START: filter_text=''
[2025-12-30 09:07:29.456] [ui.sh:983] Padding: visible=15, initial=15, padding=0
```

Each log entry includes:
- **Timestamp**: Millisecond precision
- **Source**: File and line number
- **Message**: Debug information

#### What Gets Logged

The debug system logs:
- Function entry/exit points
- Variable values at key decision points
- UI rendering events (for interactive commands)
- Filter and selection changes
- Terminal size changes
- Performance-critical calculations

#### Debug Functions

Use `debug_log()` in your code:

```bash
debug_log "Variable value: var=$var"
debug_log "=== Function START ==="
debug_log "Calculation result: x=$x, y=$y"
```

The log will only write if `AK_DEBUG=1` is set, so there's no performance impact in normal usage.

### Manual Testing

Always test your changes with:

1. **Direct source testing**: `./src/ak <command>`
2. **Build testing**: `./build.sh && ./build/ak <command>`
3. **Multiple devices**: Test with 0, 1, and multiple connected devices
4. **Edge cases**: Empty input, invalid input, missing packages, etc.

### Testing Checklist

- [ ] Command works with no devices connected
- [ ] Command works with single device
- [ ] Command works with multiple devices
- [ ] Help message displays correctly (`ak command --help`)
- [ ] Tab completion works (if applicable)
- [ ] Error messages are clear and helpful
- [ ] No shell linting errors

## Pull Request Process

1. **Update Documentation**: Update README.md and CHANGELOG.md if needed
2. **Test Thoroughly**: Run through the testing checklist
3. **Commit Messages**: Use conventional commit format:
   - `feat:` - New feature
   - `fix:` - Bug fix
   - `docs:` - Documentation changes
   - `refactor:` - Code refactoring
   - `test:` - Test changes
   - `chore:` - Maintenance tasks

4. **Create Pull Request**: 
   - Provide a clear description of changes
   - Reference any related issues
   - Include screenshots if UI changes are involved

5. **Code Review**: Address any feedback from maintainers

## Community Guidelines

- Be respectful and constructive
- Help others when you can
- Report bugs with clear reproduction steps
- Suggest features with use cases
- Write clear commit messages

## Questions?

- **Issues**: [GitHub Issues](https://github.com/luminousvault/adb-extensions/issues)
- **Discussions**: [GitHub Discussions](https://github.com/luminousvault/adb-extensions/discussions)

Thank you for contributing to ADB Extensions Kit!
