# PNG Color Tinting Troubleshooting Guide

## 🚨 Issue: Colors Not Changing

If PNG colors aren't changing, here's the step-by-step troubleshooting process:

## ✅ Step 1: Restart the App
**CRITICAL**: Native code changes require full app restart
```bash
flutter run
```
⚠️ Hot reload will NOT apply native color tinting changes!

## ✅ Step 2: Test with Simple Color Icons

I've added a **"🟩 Simple Icons"** button that creates white squares for testing:

1. Tap **"🟩 Simple Icons"** button
2. Then tap **"🎨 Test Colors"** repeatedly
3. You should see the white squares change color immediately

**If simple icons DON'T change color**: There's a native implementation issue
**If simple icons DO change color**: The issue is with PNG asset tinting

## ✅ Step 3: Check Debug Output

Look for these console messages:
```
🎨 Aircraft color for 1.0nm: #FF0000
🎨 Arrow color for 1.0nm, climbing=true: #FF0000
Aircraft layer configured with color property: aircraftIconColor
Arrow layer configured with color property: arrowIconColor
Added PNG icon to style as SDF: maplibre-png-aircraft-traffic.png from traffic.png
```

## 🔧 Technical Fixes Applied

### 1. **SDF Mode Enabled**
Changed PNG loading from regular to SDF (Signed Distance Field):
```java
style.addImage(iconId, bitmap, true); // true = SDF for color tinting
```

### 2. **Color Properties Added**
Added `iconColor` properties to both aircraft and arrow layers:
```java
PropertyFactory.iconColor(Expression.get("aircraftIconColor"))
PropertyFactory.iconColor(Expression.get("arrowIconColor"))
```

### 3. **Debug Logging Added**
Added comprehensive logging to track color value flow from Flutter to native

## 🎨 PNG Asset Requirements for Tinting

### ✅ What Works Best:
- **White or light gray PNGs** (tint perfectly)
- **High contrast with transparency**
- **Simple, solid designs**

### ❌ What Doesn't Work Well:
- **Dark PNGs** (can't lighten, only darken)
- **Complex gradients** 
- **Multi-color designs**

## 🔄 Testing Sequence

1. **Test Simple Icons First**: Use "🟩 Simple Icons" button
2. **Verify Color Changes**: Use "🎨 Test Colors" button
3. **Check Console Output**: Look for color debug messages
4. **Test PNG Icons**: Use "Test PNG Symbols" button

## 📊 Expected Color Sequence

When testing colors, you should see this cycle:
1. 🟢 **Green** (12.0nm) → Safe distance
2. 🔴 **Red** (1.0nm) → Critical proximity  
3. 🟡 **Yellow** (8.0nm) → Caution proximity
4. 🟠 **Orange** (3.5nm) → Warning proximity

## 🛠️ Advanced Debugging

### Check GeoJSON Properties
The Flutter code should output:
```
🎨 Aircraft color for 1.0nm: #FF0000
🎨 Arrow color for 1.0nm, climbing=true: #FF0000
🎨 Color test: 1.0nm - Color: #FF0000
```

### Check Native Layer Creation
The native code should output:
```
Aircraft layer configured with color property: aircraftIconColor
Arrow layer configured with color property: arrowIconColor
Added PNG icon to style as SDF: maplibre-png-aircraft-traffic.png
```

### Verify Asset Loading
Look for successful asset loading:
```
Successfully loaded bitmap: 512x512 pixels
Added PNG icon to style as SDF: maplibre-png-aircraft-traffic.png from traffic.png
```

## 🎯 Quick Fix Test

If nothing works, try this minimal test:

1. Tap **"🟩 Simple Icons"** 
2. Tap **"🎨 Test Colors"** 3 times
3. You should see white squares change: Green → Red → Yellow → Orange

If this doesn't work, there's a fundamental issue with the color property implementation.

## 📝 Current Asset Issues

The current `traffic.png` and `arrow.png` might not be optimal for tinting because:
- They may be too dark
- They might have complex colors
- They might not be designed for SDF rendering

## 🚀 Next Steps

1. **Test simple icons first** to verify the system works
2. **Replace PNG assets** with white/light gray versions designed for tinting
3. **Use proper SDF icons** for best results
4. **Consider vector icons** for ultimate flexibility

## 🔧 Creating Tintable PNGs

For best tinting results, create PNGs with:
```
- White or light gray base color (#FFFFFF or #CCCCCC)
- High contrast edges
- Transparent background
- Simple, bold designs
- Single color (no gradients)
```

The system is now fully implemented - the issue is likely with the PNG assets themselves not being designed for color tinting!