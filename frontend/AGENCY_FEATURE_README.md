# Travel Agency Integration Feature

## Overview
This feature adds a comprehensive travel agency contact and information system to the Travel Buddy app. Users can now browse partner travel agencies, view their details, and contact them directly from within the app.

## Files Created/Modified

### New Files Created:

1. **`lib/models/travel_agency.dart`**
   - Defines the `TravelAgency` class with properties:
     - Basic Info: `name`, `description`, `id`
     - Contact: `phone`, `email`, `address`, `instagram`, `website`
     - Services: `services` (list of services offered)
     - Ratings: `rating`, `reviews`
     - Media: `imageUrl`
     - Coverage: `operatingCities` (list of cities where agency operates)
   - Includes `mockAgencies` with two real agencies:
     - **Venture Voyage Treks & Tours** (Karachi-based)
     - **TN7Sky Tour & Travels** (Islamabad-based)

2. **`lib/screens/modules/agency_list_bottom_sheet.dart`**
   - Displays list of available travel agencies in a bottom sheet modal
   - Features:
     - Agency cards with name, rating, description
     - Service tags preview (shows first 3 services)
     - Phone number display
     - Tap to view full details
   - Beautiful UI with gradient backgrounds and icons

3. **`lib/screens/modules/agency_details_screen.dart`**
   - Full-page agency profile screen showing:
     - Agency header with gradient background
     - Star rating and review count
     - Complete description
     - All services offered (as tags)
     - Operating cities
     - Full contact information:
       - Phone
       - Email
       - Address
       - Website
       - Instagram
     - Action buttons:
       - "Call" button (launches phone dialer)
       - "Email" button (launches email client)
       - "Visit Website" button (opens website)
   - All contact methods are clickable and launch appropriate apps

### Modified Files:

**`lib/screens/modules/start_journey_screen.dart`**
- Added imports for `TravelAgency` model and `AgencyListBottomSheet`
- Added "Need Travel Agency?" section in the bottom controls
- Features a prominent card with:
  - Business icon
  - "Need Travel Agency?" heading
  - "Connect with trusted agencies" subheading
  - Arrow button to open agency list
- Positioned above the transport mode selector

## User Experience Flow

1. **On Start Journey Screen**: User sees a blue gradient "Need Travel Agency?" card in the bottom panel
2. **Click Card/Arrow**: Opens a bottom sheet modal displaying:
   - List of partner agencies
   - Each agency card shows: name, rating, brief description, services, phone
3. **Select Agency**: Tapping an agency card navigates to detailed profile page
4. **View Details**: On agency details page, user can:
   - Read full description
   - See all services offered
   - Check operating cities
   - View contact information
5. **Contact Agency**: User can:
   - Click phone icon → Direct call
   - Click email icon → Send email
   - Click website icon → Open website
   - Click Instagram icon → Open Instagram profile
   - Use "Call", "Email", or "Visit Website" action buttons at bottom

## Agency Data Structure

```dart
TravelAgency(
  id: String,                      // Unique identifier
  name: String,                    // Agency name
  description: String,             // Full description
  phone: String,                   // Phone number
  email: String,                   // Email address
  address: String,                 // Physical address
  instagram: String,               // Instagram handle
  website: String,                 // Website URL
  services: List<String>,          // Services offered
  rating: double,                  // Star rating (0-5)
  reviews: int,                    // Number of reviews
  imageUrl: String,                // Image URL
  operatingCities: List<String>,   // Cities where agency operates
)
```

## Extracted Agency Information

### Agency 1: Venture Voyage Treks & Tours
- **Phone**: +92 334 335 3061
- **Email**: ventures@voyagetours.pk
- **Address**: SHOP # LG-10, CANTONMENT SHOPPING MALL, Karachi, Pakistan, 75260
- **Instagram**: @venturevoyage.pk
- **Website**: venturevoyage.pk
- **Rating**: 4.8/5 (156 reviews)
- **Services**: Corporate Tours, Customized Tours, Company Tours, Transport Services, Coasters, Grand Cabins, Sedans
- **Operating Cities**: Karachi, Islamabad, Lahore, Hunza

### Agency 2: TN7Sky Tour & Travels
- **Phone**: +92 310 850 3528
- **Email**: tn7skytourspvtltd@gmail.com
- **Address**: Tarnol Islamabad, Islamabad, 44009
- **Instagram**: @tn7sky.tours_pvt_ltd
- **Website**: tn7skytourtravels.store
- **Rating**: 4.9/5 (209 reviews)
- **Services**: Tours, Rent A Car Service, Trip Planning, Transportation, Holiday Packages, Group Trips
- **Operating Cities**: Islamabad, Rawalpindi, Karachi, Lahore, Naran-Kaghan, Kashmir

## Integration Points

### Dependencies Used
- `url_launcher: ^6.3.0` - For launching phone, email, web, and social media links

### Firebase Integration
- No Firebase changes needed for basic agency display
- Future: Can store agencies in Firestore and fetch dynamically

## Future Enhancement Ideas

1. **Backend Integration**: 
   - Store agencies in Firebase Firestore
   - Fetch agencies based on user location or destination
   - Add admin panel to manage agencies

2. **Features**:
   - Agency reviews and ratings from users
   - Book tours directly from app
   - Agency availability calendar
   - Save favorite agencies
   - Filter agencies by services or location
   - Search functionality for agencies

3. **UI Improvements**:
   - Add actual agency logos/images
   - Implement photo gallery for each agency
   - Add agency opening hours
   - Show distance to nearest agency office
   - Agency verification badges

## Testing

To test the agency feature:

1. Open the Start Journey screen
2. Look for the blue "Need Travel Agency?" card in the bottom panel
3. Click the arrow/card to open the agency list
4. Review the two partner agencies
5. Click on an agency to see full details
6. Test the contact buttons (phone, email, website, Instagram)

## Color Scheme

- **Primary Color**: `#1E66F5` (Blue)
- **Agency Card**: Blue gradient (`Colors.blue[600]` to `Colors.blue[800]`)
- **Action Buttons**: Primary blue for "Call", Gray for "Email", Green for "Visit Website"
- **Service Tags**: Light blue background with blue text
- **Location Tags**: Light green background with green text

## Notes

- All contact functionality uses `url_launcher` package
- Agency data is currently hardcoded (mockAgencies) for demonstration
- No real calls/emails are sent - the app just launches the device's default apps
- Both agencies are real Pakistani travel agencies (extracted from Instagram profiles)

