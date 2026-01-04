# KSAPDismiss Makefile

.PHONY: all build clean install xcode

# Default target
all: build

# Build with Xcode command line tools
build:
	@echo "Building KSAPDismiss..."
	@if command -v xcodebuild &> /dev/null && [ -f "KSAPDismiss.xcodeproj/project.pbxproj" ]; then \
		xcodebuild -project KSAPDismiss.xcodeproj -scheme KSAPDismiss -configuration Release build; \
	else \
		echo "No Xcode project found. Building with Swift Package Manager..."; \
		swift build -c release; \
	fi

# Generate Xcode project using xcodegen
xcode:
	@echo "Generating Xcode project..."
	@if command -v xcodegen &> /dev/null; then \
		xcodegen generate; \
		echo "Xcode project generated successfully!"; \
	else \
		echo "xcodegen not found. Install with: brew install xcodegen"; \
		echo "Or create project manually in Xcode."; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf .build
	@rm -rf build
	@rm -rf DerivedData
	@swift package clean 2>/dev/null || true

# Install to /Applications
install: build
	@echo "Installing KSAPDismiss..."
	@if [ -d "build/Release/KSAPDismiss.app" ]; then \
		cp -r build/Release/KSAPDismiss.app /Applications/; \
		echo "Installed to /Applications/KSAPDismiss.app"; \
	else \
		echo "Build the app with Xcode first for proper installation."; \
	fi

# Create app bundle from SPM build (workaround)
bundle:
	@echo "Creating app bundle from SPM build..."
	@mkdir -p "KSAPDismiss.app/Contents/MacOS"
	@mkdir -p "KSAPDismiss.app/Contents/Resources"
	@mkdir -p "KSAPDismiss.app/Contents/Library/LaunchServices"
	@if [ -f ".build/release/KSAPDismissApp" ]; then \
		cp ".build/release/KSAPDismissApp" "KSAPDismiss.app/Contents/MacOS/KSAPDismiss"; \
	elif [ -f ".build/debug/KSAPDismissApp" ]; then \
		cp ".build/debug/KSAPDismissApp" "KSAPDismiss.app/Contents/MacOS/KSAPDismiss"; \
	fi
	@cp "KSAPDismiss/Info.plist" "KSAPDismiss.app/Contents/"
	@# Copy resource bundle for i18n (SPM expects bundle in Contents/, not Resources/)
	@for arch in arm64-apple-macosx x86_64-apple-macosx; do \
		for config in release debug; do \
			if [ -d ".build/$$arch/$$config/KSAPDismiss_KSAPDismiss.bundle" ]; then \
				cp -r ".build/$$arch/$$config/KSAPDismiss_KSAPDismiss.bundle" "KSAPDismiss.app/Contents/"; \
				break 2; \
			fi; \
		done; \
	done
	@/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable KSAPDismiss" "KSAPDismiss.app/Contents/Info.plist"
	@echo "App bundle created at KSAPDismiss.app"
	@echo "Note: Helper tool requires Xcode build with proper signing for SMJobBless."

# Build helper tool (requires Xcode project)
helper:
	@echo "Building privileged helper..."
	@if [ -f "KSAPDismiss.xcodeproj/project.pbxproj" ]; then \
		xcodebuild -project KSAPDismiss.xcodeproj -target KSAPDismissHelper -configuration Release build; \
		echo "Helper built. Copy to app bundle with: make embed-helper"; \
	else \
		echo "Error: Xcode project required. Run 'make xcode' first."; \
		exit 1; \
	fi

# Embed helper into app bundle (after building both)
embed-helper:
	@echo "Embedding helper into app bundle..."
	@HELPER_PATH=$$(find build -name "com.hxd.ksapdismiss.helper" -type f 2>/dev/null | head -1); \
	if [ -n "$$HELPER_PATH" ] && [ -f "$$HELPER_PATH" ]; then \
		mkdir -p "KSAPDismiss.app/Contents/Library/LaunchServices"; \
		cp "$$HELPER_PATH" "KSAPDismiss.app/Contents/Library/LaunchServices/"; \
		echo "Helper embedded at KSAPDismiss.app/Contents/Library/LaunchServices/com.hxd.ksapdismiss.helper"; \
	else \
		echo "Error: Helper not found. Run 'make helper' first."; \
		exit 1; \
	fi

# Run the app
run: bundle
	@echo "Running KSAPDismiss..."
	@open "KSAPDismiss.app"

# Help
help:
	@echo "KSAPDismiss Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build the application (default)"
	@echo "  build        - Build with xcodebuild or SPM"
	@echo "  xcode        - Generate Xcode project (requires xcodegen)"
	@echo "  bundle       - Create .app bundle from SPM build"
	@echo "  helper       - Build privileged helper (requires Xcode)"
	@echo "  embed-helper - Embed helper into app bundle"
	@echo "  run          - Build, bundle, and run the app"
	@echo "  install      - Install to /Applications"
	@echo "  clean        - Remove build artifacts"
	@echo "  help         - Show this help"
	@echo ""
	@echo "For SMJobBless helper to work:"
	@echo "  1. make xcode       # Generate Xcode project"
	@echo "  2. make build       # Build app with helper embedded"
	@echo "  3. Sign with valid Apple Developer certificate"
