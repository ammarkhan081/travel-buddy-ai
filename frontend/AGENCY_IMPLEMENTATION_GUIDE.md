# Travel Agency Feature - Visual & Technical Guide

## Feature Architecture

```
StartJourneyScreen
    ├── Map Display
    ├── Search Bar
    └── Bottom Controls Panel
        ├── Contact Agency Card (NEW)
        │   └── Tap → Open AgencyListBottomSheet
        ├── Transport Mode Selector
        └── Start Journey Button

AgencyListBottomSheet (Modal)
    └── List of TravelAgency Items
        └── Each Card Tap → Navigate to AgencyDetailsScreen

AgencyDetailsScreen (Full Page)
    ├── Header with Agency Name
    ├── Rating & Reviews
    ├── Description
    ├── Services (Chips)
    ├── Operating Cities (Chips)
    ├── Contact Information
    │   ├── Phone (Clickable)
    │   ├── Email (Clickable)
    │   ├── Address
    │   ├── Website (Clickable)
    │   └── Instagram (Clickable)
    └── Action Buttons
        ├── Call Button
        ├── Email Button
        └── Visit Website Button
```

## UI Mockup - Contact Agency Card

```
┌────────────────────────────────────────────┐
│ 🏢 Need Travel Agency?                     │ ➜
│    Connect with trusted agencies           │
└────────────────────────────────────────────┘
```

## UI Mockup - Agency List Bottom Sheet

```
═════════════════════════════════════════════════════
                  Partner Agencies
    🌍 Connect with trusted travel agencies
─────────────────────────────────────────────────────

┌─────────────────────────────────────────────────┐
│ 🏢 Venture Voyage Treks & Tours            ➜    │
│    ⭐ 4.8 (156 reviews)                        │
│    Eco tour agency offering Corporate...       │
│    Corporate Tours, Customized Tours...        │
│    📞 +92 334 335 3061                        │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ 🏢 TN7Sky Tour & Travels                  ➜     │
│    ⭐ 4.9 (209 reviews)                        │
│    Professional tour agency providing...       │
│    Tours, Rent A Car Service, Trip Pl...      │
│    📞 +92 310 850 3528                        │
└─────────────────────────────────────────────────┘
```

## UI Mockup - Agency Details Screen

```
═════════════════════════════════════════════════════
                 Venture Voyage Treks & Tours
              [Gradient Background with Icon]
─────────────────────────────────────────────────────

┌──────────────────────────────────────┐
│ ⭐ 4.8 (156 reviews)                 │
└──────────────────────────────────────┘

About
─────────────────────────────────────────────────────
Eco tour agency offering Corporate, Customized and 
Company Tours with premium transport services.

Services
─────────────────────────────────────────────────────
[Corporate Tours] [Customized Tours] [Company Tours]
[Transport Services] [Coasters] [Grand Cabins] [Sedans]

Operating Cities
─────────────────────────────────────────────────────
[📍 Karachi] [📍 Islamabad] [📍 Lahore] [📍 Hunza]

Contact Information
─────────────────────────────────────────────────────
📞 Phone: +92 334 335 3061              →
📧 Email: ventures@voyagetours.pk       →
📍 Address: SHOP # LG-10...             
🌐 Website: venturevoyage.pk            →
📷 Instagram: @venturevoyage.pk         →

[   📞 Call   ] [   📧 Email   ]
[        🌐 Visit Website       ]

═════════════════════════════════════════════════════
```

## Data Flow Diagram

```
┌──────────────┐
│ User clicks  │
│ "Need Travel │
│   Agency?"   │
└──────┬───────┘
       │
       ▼
┌──────────────────────┐
│ showModalBottomSheet │
│ with                 │
│ AgencyListBottomSheet│
└──────┬───────────────┘
       │
       ▼
┌──────────────────────────┐
│ Display list of agencies │
│ from                     │
│ TravelAgency.mockAgencies│
└──────┬───────────────────┘
       │
       ├─ User taps agency ─┐
       │                    │
       ▼                    ▼
   [Close]          ┌────────────────┐
   Modal            │ Navigate to    │
                    │ AgencyDetails  │
                    │ Screen         │
                    └────────┬───────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                    ▼                 ▼
              [Click Contact]  [View Info]
                    │                 │
        ┌───────────┼─────────┐      │
        ▼           ▼         ▼      │
    [Call]     [Email]   [Website] [Read]
        │           │         │      │
        ▼           ▼         ▼      ▼
    [tel://] [mailto://] [https://] [Display]
```

## State Management

The feature uses simple Flutter state management with `setState`:

```dart
class _StartJourneyScreenState extends State<StartJourneyScreen> {
  // Existing state variables
  
  // Agency feature doesn't require new state
  // Modal is opened via showModalBottomSheet
  // Navigation is handled by MaterialPageRoute
}
```

## Color Palette

| Component | Color | Hex Code | Usage |
|-----------|-------|----------|-------|
| Primary | Blue | #1E66F5 | Main buttons, selected states |
| Card Gradient Start | Light Blue | #2D6FFF | Agency card top |
| Card Gradient End | Dark Blue | #1E3FA0 | Agency card bottom |
| Service Tag BG | Light Blue (10% opacity) | #1E66F526 | Service chip background |
| Service Tag Text | Blue | #1E66F5 | Service chip text |
| City Tag BG | Light Green | #10B98110 | City chip background |
| City Tag Text | Green | #10B981 | City chip text |
| Background | White | #FFFFFF | Main background |
| Text Primary | Black | #000000 | Main text |
| Text Secondary | Gray 600 | #4B5563 | Secondary text |

## Code Organization

```
lib/
├── models/
│   └── travel_agency.dart ............................ (NEW)
├── screens/
│   └── modules/
│       ├── start_journey_screen.dart ................ (MODIFIED)
│       ├── agency_list_bottom_sheet.dart ........... (NEW)
│       └── agency_details_screen.dart .............. (NEW)
└── ...
```

## Dependencies

The feature uses:
- `url_launcher: ^6.3.0` - Already in pubspec.yaml
- No new dependencies needed!

## Key Methods

### In TravelAgency Model
```dart
// Create from JSON (for future backend integration)
factory TravelAgency.fromJson(Map<String, dynamic> json)

// Convert to JSON (for future backend integration)
Map<String, dynamic> toJson()

// Mock data (currently used)
static final List<TravelAgency> mockAgencies
```

### In AgencyDetailsScreen
```dart
// Launch phone call
Future<void> _launchPhone(String phone) async

// Launch email
Future<void> _launchEmail(String email) async

// Launch website
Future<void> _launchWebsite(String website) async

// Launch Instagram
Future<void> _launchInstagram(String instagram) async
```

## Implementation Notes

1. **Modal Bottom Sheet**: Uses `showModalBottomSheet` for a smooth, native-like experience
2. **Navigation**: Uses `MaterialPageRoute` for full-page details view
3. **URL Launcher**: Safely checks if URLs can be launched before attempting
4. **Responsive Design**: All UI adapts to different screen sizes
5. **Error Handling**: Graceful fallbacks if app links fail

## Testing Checklist

- [ ] Contact Agency card appears on Start Journey screen
- [ ] Clicking card opens agency list bottom sheet
- [ ] Agency cards display correct information
- [ ] Clicking agency card navigates to details screen
- [ ] All contact buttons are clickable
- [ ] Phone button launches dialer
- [ ] Email button launches email app
- [ ] Website button opens browser
- [ ] Instagram button opens Instagram app
- [ ] Back navigation works properly
- [ ] No console errors or warnings

## Future Backend Integration

To integrate with Firebase:

```dart
// In TravelAgency service
Future<List<TravelAgency>> fetchAgencies() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('travel_agencies')
      .get();
  
  return snapshot.docs
      .map((doc) => TravelAgency.fromJson(doc.data()))
      .toList();
}
```

## Performance Considerations

- Agency list is static (mockAgencies) - excellent performance
- No network calls on agency view
- Bottom sheet is lazy-loaded when user taps the card
- URL launcher is native (no network overhead)
- All UI is optimized with const constructors

