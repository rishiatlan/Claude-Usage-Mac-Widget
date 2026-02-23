#!/bin/bash

# Script to generate app icon based on icon.svg design

ICON_NAME="AppIcon"
ICONSET_DIR="build/${ICON_NAME}.iconset"
ICNS_FILE="build/${ICON_NAME}.icns"

echo "Generating app icon..."

# Create iconset directory
mkdir -p "${ICONSET_DIR}"

# Generate icon using Swift script that recreates the SVG design
swift - <<'SWIFT'
import Cocoa

// Create icon matching the SVG design
func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    // Apple blue background (#007AFF)
    let backgroundColor = NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)

    // Rounded rectangle background
    let cornerRadius = size * (110.0 / 512.0) // Scale corner radius proportionally
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    backgroundColor.setFill()
    path.fill()

    // Calculate circle dimensions (scaled from 512px base)
    let center = NSPoint(x: size / 2, y: size / 2)
    let radius = size * (150.0 / 512.0)
    let strokeWidth = size * (35.0 / 512.0)

    // Background circle (20% opacity white)
    let backgroundCircle = NSBezierPath()
    backgroundCircle.lineWidth = strokeWidth
    backgroundCircle.lineCapStyle = .round
    backgroundCircle.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 0,
        endAngle: 360,
        clockwise: false
    )
    NSColor.white.withAlphaComponent(0.2).setStroke()
    backgroundCircle.stroke()

    // Progress arc (75% of circle, white)
    // The SVG uses stroke-dasharray="707 942" which is about 75% of circumference
    let progressCircle = NSBezierPath()
    progressCircle.lineWidth = strokeWidth
    progressCircle.lineCapStyle = .round
    progressCircle.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 90,  // Start at top
        endAngle: 90 - 270,  // Go 75% around (270 degrees)
        clockwise: true
    )
    NSColor.white.setStroke()
    progressCircle.stroke()

    // Draw "%" symbol
    let fontSize = size * (160.0 / 512.0)
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]

    let text = "%"
    let textSize = text.size(withAttributes: attrs)
    // The SVG has y="275" which is slightly below center (256+19)
    let yOffset = size * (19.0 / 512.0)
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 + yOffset,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attrs)

    image.unlockFocus()

    return image
}

// Generate all required icon sizes
let sizes = [
    ("icon_16x16", 16.0),
    ("icon_16x16@2x", 32.0),
    ("icon_32x32", 32.0),
    ("icon_32x32@2x", 64.0),
    ("icon_128x128", 128.0),
    ("icon_128x128@2x", 256.0),
    ("icon_256x256", 256.0),
    ("icon_256x256@2x", 512.0),
    ("icon_512x512", 512.0),
    ("icon_512x512@2x", 1024.0)
]

for (name, size) in sizes {
    let icon = createIcon(size: CGFloat(size))

    if let tiffData = icon.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        let filename = "build/AppIcon.iconset/\(name).png"
        try? pngData.write(to: URL(fileURLWithPath: filename))
        print("Generated \(name).png")
    }
}

print("Icon generation complete!")
SWIFT

if [ $? -eq 0 ]; then
    # Convert iconset to icns
    echo "Converting to .icns format..."
    iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_FILE}"

    if [ $? -eq 0 ]; then
        echo "Icon created successfully at ${ICNS_FILE}"

        # Clean up iconset directory
        rm -rf "${ICONSET_DIR}"
    else
        echo "Failed to convert to .icns"
        exit 1
    fi
else
    echo "Failed to generate icon images"
    exit 1
fi
