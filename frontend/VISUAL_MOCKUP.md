# Travel Agency Feature - Visual Mockup & Screenshots

## 📱 Screen Layouts

### Screen 1: Start Journey Screen (With New Agency Card)

```
┌─────────────────────────────────────────┐
│              10:35  ≋  ◰  📶            │
├─────────────────────────────────────────┤
│                                         │
│        🗺 Map Display Area 🗺           │
│     (Shows current location & route)    │
│                                         │
│                                         │
│                                         │
│                                         │
│                                         │
│                                         │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│  📍 From: Current Location              │
│  ─────────────────────────────────────  │
│  📌 To: Search Destination...           │
│  (Search suggestions appear here)       │
├─────────────────────────────────────────┤
│  ╔═════════════════════════════════════╗│
│  ║ 🏢 Need Travel Agency?          ➜   ║│ ← NEW FEATURE
│  ║    Connect with trusted agencies    ║│
│  ╚═════════════════════════════════════╝│
│                                         │
│  [🚗 Mini]  [🏍 Moto]  [🚂 City]   │
│  [✈️ Plane]                            │
│                                         │
│         [Start My Journey]              │
│                                         │
└─────────────────────────────────────────┘
```

### Screen 2: Agency List Bottom Sheet (Modal)

```
┌─────────────────────────────────────────┐
│ ▬ ▬ ▬ ▬ ▬ (Handle bar)                 │
├─────────────────────────────────────────┤
│ 🌍 Partner Agencies                     │
│    Connect with trusted travel agencies │
├─────────────────────────────────────────┤
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │🏢 Venture Voyage Treks & Tours  ➜   │ │
│ │   ⭐ 4.8 (156 reviews)              │ │
│ │   Eco tour agency offering          │ │
│ │   Corporate, Customized Tours...    │ │
│ │   [Corporate] [Tours] [Services]    │ │
│ │   +2 more services                  │ │
│ │   📞 +92 334 335 3061              │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │🏢 TN7Sky Tour & Travels         ➜   │ │
│ │   ⭐ 4.9 (209 reviews)              │ │
│ │   Professional tour agency          │ │
│ │   providing tours and rental...     │ │
│ │   [Tours] [Rent A Car] [Trips]     │ │
│ │   +3 more services                  │ │
│ │   📞 +92 310 850 3528              │ │
│ └─────────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

### Screen 3: Agency Details - Top Section

```
┌─────────────────────────────────────────┐
│  ◀ Venture Voyage Treks & Tours      ⋯ │
├─────────────────────────────────────────┤
│                                         │
│    [Gradient Blue Background with 🌍]   │
│                                         │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ ⭐ 4.8 (156 reviews)                │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ About                                   │
│ ─────────────────────────────────────── │
│ Eco tour agency offering Corporate,     │
│ Customized and Company Tours with       │
│ premium transport services.             │
│                                         │
│ Services                                │
│ ─────────────────────────────────────── │
│ [Corporate Tours][Customized Tours]    │
│ [Company Tours][Transport][Coasters]   │
│ [Grand Cabins][Sedans]                 │
│                                         │
│ Operating Cities                        │
│ ─────────────────────────────────────── │
│ [📍 Karachi][📍 Islamabad]             │
│ [📍 Lahore][📍 Hunza]                  │
│                                         │
└─────────────────────────────────────────┘
```

### Screen 4: Agency Details - Contact Section

```
┌─────────────────────────────────────────┐
│ Contact Information                     │
│ ─────────────────────────────────────── │
│                                         │
│ 📞 Phone: +92 334 335 3061         ➜   │
│                                         │
│ 📧 Email: ventures@voyagetours.pk   ➜  │
│                                         │
│ 📍 Address: SHOP # LG-10,              │
│    CANTONMENT SHOPPING MALL             │
│    Karachi, Pakistan 75260             │
│                                         │
│ 🌐 Website: venturevoyage.pk        ➜  │
│                                         │
│ 📷 Instagram: @venturevoyage.pk     ➜  │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────┬──────────────────┐  │
│  │ 📞 Call      │ 📧 Email         │  │
│  └──────────────┴──────────────────┘  │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │ 🌐 Visit Website                │  │
│  └─────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

## 🎨 Color Breakdown

### Agency Card (Start Journey)
```
┌────────────────────────────────┐
│ #2D6FFF (Light Blue)           │ ← Top
│ Gradient to #1E3FA0 (Dark Blue)│ ← Bottom
│                                │
│ 🏢 Need Travel Agency?         │
│    Connect with trusted ...    │
│                                │
│                    ➜           │
└────────────────────────────────┘
```

### Service Chips
```
┌──────────────────┐
│ Background:      │
│ #1E66F526        │ Light Blue (10% opacity)
│                  │
│ [Corporate Tours]│
│                  │
│ Text: #1E66F5    │ Primary Blue
│ Weight: Bold     │
└──────────────────┘
```

### City Chips
```
┌──────────────────┐
│ Background:      │
│ #10B98110        │ Light Green (10% opacity)
│                  │
│ [📍 Karachi]     │
│                  │
│ Text: #10B981    │ Green
│ Weight: Bold     │
└──────────────────┘
```

## 📊 Component Breakdown

### 1. Agency Card Component (List Item)

```
┌─────────────────────────────────┐
│ ┌──────┐                         │
│ │ 🏢   │ Agency Name       ➜     │
│ │      │ ⭐ 4.8 (156)           │
│ └──────┘                         │
│ Brief description...             │
│ [Service1] [Service2] [Service3] │
│ +2 more services                 │
│ 📞 +92 334 335 3061             │
└─────────────────────────────────┘
```

### 2. Details Card Component

```
┌─────────────────────────────────┐
│ 📞 Phone                        │
│ +92 334 335 3061          ➜    │
└─────────────────────────────────┘
```

### 3. Action Button Component

```
┌─────────────────────────────────┐
│ 📞 Call                         │
│ (Tap to launch dialer)          │
└─────────────────────────────────┘

Color: #1E66F5 (Primary Blue)
Text: White
Padding: 14px vertical
Border Radius: 12px
```

## 🔄 Interaction Flow Diagram

```
┌──────────────────────┐
│ Start Journey Screen  │
└──────────┬───────────┘
           │
      [User Taps]
           │
           ▼
┌──────────────────────┐
│ "Need Travel Agency?"│
│ Card Shows           │
└──────────┬───────────┘
           │
      [User Taps Card]
           │
           ▼
┌──────────────────────┐
│ Bottom Sheet Opens   │
│ (Slide up animation) │
│ Agency List          │
└──────────┬───────────┘
           │
      [User Selects]
           │
           ▼
┌──────────────────────┐
│ Agency Details Page  │
│ (Push animation)     │
│ Full Information     │
└──────────┬───────────┘
           │
      [User Taps Contact]
           │
           ├─────────┬────────┬──────────┐
           ▼         ▼        ▼          ▼
         Phone    Email   Website    Instagram
           │         │        │          │
           ▼         ▼        ▼          ▼
        [Dialer] [Email]  [Browser]  [Insta App]
```

## 🎯 Responsive Behavior

### Phone (360dp width)
- Single column layout
- Full-width buttons
- Wrapped service chips

### Tablet (600dp+ width)
- Same single column
- Maintained padding
- Scalable components

All text respects system text scaling preferences.

## ⏱️ Animation Timings

| Animation | Duration | Easing |
|-----------|----------|--------|
| Bottom Sheet Slide Up | 300ms | EaseOut |
| Page Push Transition | 300ms | EaseInOut |
| Button Tap Feedback | 100ms | Linear |
| Card Hover Effect | 200ms | EaseInOut |

## 🎨 Typography

| Element | Font Size | Weight | Color |
|---------|-----------|--------|-------|
| Agency Name | 16sp | Bold | Black |
| Rating | 12sp | Semi-Bold | Gray 600 |
| Description | 14sp | Regular | Gray 600 |
| Service Chip | 10sp | Semi-Bold | Primary Blue |
| Phone Number | 11sp | Medium | Gray 600 |
| Section Header | 18sp | Bold | Gray 800 |

## 📐 Spacing

| Element | Spacing |
|---------|---------|
| Card Padding | 12dp |
| Section Margin | 24dp |
| Chip Spacing | 6-8dp |
| Button Height | 56dp |
| Action Button Margin | 12dp |

## ✨ Visual Effects

- **Gradient**: LinearGradient for agency cards
- **Shadows**: Subtle shadows on cards for depth
- **Border Radius**: 12-16dp for modern look
- **Icons**: Consistent 24-28dp sizes
- **Opacity**: Used for hover/disabled states

## 📱 Screen Sizes Tested

- ✅ Small Phone (360dp)
- ✅ Standard Phone (412dp)
- ✅ Large Phone (480dp)
- ✅ Tablet (600dp)
- ✅ Large Tablet (720dp)

All screens maintain visual hierarchy and usability.

