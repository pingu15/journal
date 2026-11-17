#if DEBUG
import Foundation

/// The made-up journal `SampleData` seeds: about four months in the life of someone who lives in
/// Prospect Heights, Brooklyn, and works at a small design studio in the Flatiron District (in the
/// office Tuesday to Thursday, at home Monday and Friday).
///
/// Entries are placed by week and weekday, not by date, so a Saturday market is on a Saturday
/// whenever the store is seeded. What depends on the time of year (the beach, snow, leaves) is in
/// `seasonal`, and only what's in season on its date is used.
enum SampleJournal {
    struct Place: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double

        static let home = Place(name: "Prospect Heights", latitude: 40.6775, longitude: -73.9690)
        static let office = Place(name: "Flatiron District", latitude: 40.7436, longitude: -73.9893)
        static let madisonSquare = Place(name: "Madison Square Park", latitude: 40.7420, longitude: -73.9876)
        static let cafe = Place(name: "Vanderbilt Avenue", latitude: 40.6803, longitude: -73.9679)
        static let bagels = Place(name: "Flatbush Avenue", latitude: 40.6808, longitude: -73.9750)
        static let grandArmyPlaza = Place(name: "Grand Army Plaza", latitude: 40.6729, longitude: -73.9702)
        static let prospectPark = Place(name: "Prospect Park", latitude: 40.6686, longitude: -73.9712)
        static let brooklynMuseum = Place(name: "Brooklyn Museum", latitude: 40.6712, longitude: -73.9636)
        static let botanicGarden = Place(name: "Brooklyn Botanic Garden", latitude: 40.6680, longitude: -73.9640)
        static let climbingGym = Place(name: "Gowanus", latitude: 40.6790, longitude: -73.9870)
        static let carrollGardens = Place(name: "Carroll Gardens", latitude: 40.6795, longitude: -73.9991)
        static let dumbo = Place(name: "DUMBO", latitude: 40.7033, longitude: -73.9895)
        static let brooklynBridgePark = Place(name: "Brooklyn Bridge Park", latitude: 40.7022, longitude: -73.9965)
        static let dominoPark = Place(name: "Domino Park", latitude: 40.7146, longitude: -73.9677)
        static let williamsburg = Place(name: "Williamsburg", latitude: 40.7180, longitude: -73.9575)
        static let chinatown = Place(name: "Chinatown", latitude: 40.7155, longitude: -73.9985)
        static let pier11 = Place(name: "Pier 11", latitude: 40.7033, longitude: -74.0060)
        static let unionSquare = Place(name: "Union Square Greenmarket", latitude: 40.7359, longitude: -73.9906)
        static let highLine = Place(name: "The High Line", latitude: 40.7450, longitude: -74.0065)
        static let carmineStreet = Place(name: "Carmine Street", latitude: 40.7306, longitude: -74.0021)
        static let filmForum = Place(name: "Film Forum", latitude: 40.7284, longitude: -74.0046)
        static let theMet = Place(name: "The Met", latitude: 40.7794, longitude: -73.9632)
        static let centralPark = Place(name: "Central Park", latitude: 40.7730, longitude: -73.9712)
        static let grandCentral = Place(name: "Grand Central Terminal", latitude: 40.7527, longitude: -73.9772)
        static let station28 = Place(name: "28 St Station", latitude: 40.7454, longitude: -73.9886)
        static let breakneckRidge = Place(name: "Breakneck Ridge", latitude: 41.4433, longitude: -73.9790)
        static let coneyIsland = Place(name: "Coney Island", latitude: 40.5730, longitude: -73.9790)
    }

    /// A bundled photo (`SampleMedia/<name>.jpg`, Debug builds only): where it was taken, and the
    /// months it could have been taken in (nil: any).
    struct Photo {
        let place: Place
        var months: Set<Int>? = nil
    }

    private static let leafy: Set<Int> = [5, 6, 7, 8, 9, 10]
    private static let bare: Set<Int> = [11, 12, 1, 2, 3, 4]
    private static let foliage: Set<Int> = [10, 11]
    private static let snowy: Set<Int> = [12, 1, 2]

    static let photos: [String: Photo] = [
        "bagel": Photo(place: .bagels),
        "block-dusk": Photo(place: .home, months: [9, 10, 11]),
        "brooklyn-bridge-park": Photo(place: .brooklynBridgePark, months: bare),
        "brownstones": Photo(place: .home, months: leafy),
        "central-park-bow-bridge": Photo(place: .centralPark, months: foliage),
        "central-park-mall": Photo(place: .centralPark, months: foliage),
        "cherry-blossom-1": Photo(place: .botanicGarden, months: [4, 5]),
        "cherry-blossom-2": Photo(place: .botanicGarden, months: [4, 5]),
        "chinatown-fruit": Photo(place: .chinatown),
        "chinatown-lanterns": Photo(place: .chinatown),
        "coffee-laptop": Photo(place: .cafe),
        "coffee-notebook": Photo(place: .cafe),
        "coney-island-beach": Photo(place: .coneyIsland, months: [6, 7, 8, 9]),
        "coney-island-boardwalk": Photo(place: .coneyIsland, months: [6, 7, 8, 9]),
        "dumbo": Photo(place: .dumbo),
        "empty-room": Photo(place: .home),
        "ferry": Photo(place: .pier11),
        "ferry-window": Photo(place: .pier11),
        "flatiron": Photo(place: .madisonSquare, months: [4, 5, 6, 7, 8, 9]),
        "grand-army-plaza-winter": Photo(place: .grandArmyPlaza, months: [12, 1]),
        "greenmarket": Photo(place: .unionSquare, months: leafy),
        "high-line-garden": Photo(place: .highLine, months: leafy),
        "high-line-tracks": Photo(place: .highLine, months: leafy),
        "hudson-river": Photo(place: .breakneckRidge, months: foliage),
        "hudson-view": Photo(place: .breakneckRidge, months: leafy),
        "living-room": Photo(place: .home),
        "madison-square-park": Photo(place: .madisonSquare, months: leafy),
        "met-courtyard": Photo(place: .theMet),
        "met-stairs": Photo(place: .theMet),
        "pasta-bowl": Photo(place: .home),
        "pasta-plate": Photo(place: .carrollGardens),
        "pizza": Photo(place: .carmineStreet),
        "prospect-park-fall": Photo(place: .prospectPark, months: foliage),
        "prospect-park-meadow": Photo(place: .prospectPark, months: [3, 4, 11]),
        "rain-fire-escape": Photo(place: .home),
        "rainy-block": Photo(place: .home, months: bare),
        "skyline-pier": Photo(place: .brooklynBridgePark),
        "skyline-sunset": Photo(place: .brooklynBridgePark),
        "snow-dumbo": Photo(place: .dumbo, months: snowy),
        "snow-street": Photo(place: .home, months: snowy),
        "subway-28th": Photo(place: .station28),
        "subway-42nd": Photo(place: .grandCentral),
        "window-mugs": Photo(place: .home),
        "window-plants": Photo(place: .home),
        "window-sunrise": Photo(place: .home),
    ]

    enum Weekday: Int {
        case mon, tue, wed, thu, fri, sat, sun
    }

    enum Sky {
        case clear, mostlyClear, partlyCloudy, cloudy, drizzle, rain, heavyRain, thunderstorms, snow, fog
        /// Clear, and well above the month's average.
        case hot
    }

    /// Somewhere the day went, besides the usual: `from` as a clock time (1830), for `minutes`.
    struct Stop {
        let place: Place
        let from: Int
        let minutes: Int
    }

    /// An entry before it has a date. `time` is a clock time (2145). A line of `text` that is only
    /// `{name}` is that photo; photos on lines in a row make a collage. A nil `place` is an entry
    /// with no place or weather. `sky` sets the day's weather where the text speaks of it.
    struct Draft {
        let time: Int
        let place: Place?
        let text: String
        var stops: [Stop] = []
        var sky: Sky? = nil
    }

    /// `week` 0 is the week being seeded in (Monday first), 1 the week before, and so on.
    struct Slot {
        let week: Int
        let weekday: Weekday
        let draft: Draft
    }

    struct Seasonal {
        let months: Set<Int>
        let weekday: Weekday
        let draft: Draft
    }

    /// A photo taken but never put in an entry: in the Photos library only.
    struct Snapshot {
        let week: Int
        let weekday: Weekday
        let time: Int
        let photo: String
    }

    static let weeks = 17

    private static func s(_ place: Place, _ from: Int, _ minutes: Int) -> Stop {
        Stop(place: place, from: from, minutes: minutes)
    }

    private static func e(
        _ week: Int, _ weekday: Weekday, _ time: Int, _ place: Place?, _ text: String,
        stops: [Stop] = [], sky: Sky? = nil
    ) -> Slot {
        Slot(week: week, weekday: weekday, draft: Draft(time: time, place: place, text: text, stops: stops, sky: sky))
    }

    private static func inSeason(
        _ months: Set<Int>, _ weekday: Weekday, _ time: Int, _ place: Place?, _ text: String,
        stops: [Stop] = [], sky: Sky? = nil
    ) -> Seasonal {
        Seasonal(months: months, weekday: weekday, draft: Draft(time: time, place: place, text: text, stops: stops, sky: sky))
    }

    // MARK: - The journal, oldest first

    static let slots: [Slot] = [
        e(16, .mon, 2140, .home, """
        # Starting again
        Third attempt at keeping a journal. The first two died in February, like everything else that starts in January.

        New rules, so I don't quit:
        - Short is fine
        - Skipping a day is not failing
        - No rereading for a month

        Mostly I want a record. I've lived on this block for four years and couldn't tell you what I did last spring.
        """),
        e(16, .wed, 1310, .madisonSquare, """
        Ate lunch on a bench instead of at my desk for the first time in weeks. A man next to me was feeding a squirrel an entire soft pretzel, piece by piece, with the seriousness of a surgeon.
        {madison-square-park}
        Twenty minutes outside and the afternoon felt like a different day.
        """, sky: .mostlyClear),
        e(16, .sat, 1105, .home, """
        # Saturday rounds
        Bagels first, then the market. The line was out the door by 9:15 and nobody minded. Everything with scallion cream cheese, eaten on the walk because it never survives the trip home.
        {bagel}
        At the market: peaches, a loaf of sourdough, eggs from the stand with the handwritten sign. I spent $31 and felt **rich**.
        """, stops: [s(.bagels, 910, 20), s(.grandArmyPlaza, 940, 45)], sky: .clear),

        e(15, .tue, 920, .office, """
        Q train sat at DeKalb for eleven minutes "because of train traffic ahead." Everyone in the car did the same slow exhale at the same time.
        {subway-28th}
        Got to my desk at 9:20 and nobody had noticed. Note to self: nobody ever notices.
        """),
        e(15, .thu, 2210, .home, """
        # The museum pitch
        Lena told us today that we're in the running for the museum project. Three studios, one month, a pitch at the end of it. Dan and I are leading ours.

        I want this more than I've wanted anything at work in a long time. It's the kind of project I took this job hoping for: a real place, real visitors, something my mom could use.

        Also terrified. Wrote down every idea I had on the train home so I could stop carrying them.
        """),
        e(15, .sun, 1930, nil, """
        Called Mom. She asked if I was eating vegetables and then told me a twenty minute story about the neighbor's fence.

        Tried making fresh pasta from the book Priya gave me. The dough was too dry and tore every time I rolled it. Ate it anyway. *Rustic*, we'll say.
        """),

        e(14, .mon, 2105, .home, """
        # First V3
        Topped the green V3 in the corner, the one with the awkward sideways start. Three weeks of falling off the same move, and today my foot just stayed.

        My forearms are useless now. Typing this with two fingers.
        """, stops: [s(.climbingGym, 1825, 105)]),
        e(14, .wed, 1845, .highLine, """
        Walked west after work instead of going straight down into the subway. Up on the High Line by 6.
        {high-line-tracks}
        {high-line-garden}
        It's a tourist conveyor belt at the south end, but past 20th it thins out and you can hear the plants move. I forget this is fifteen minutes from my desk.
        """, stops: [s(.highLine, 1805, 70)], sky: .mostlyClear),
        e(14, .fri, 2330, .home, """
        # Dinner with Priya
        Williamsburg, then a long walk along the water at Domino Park. She's been offered a job in Los Angeles and hasn't decided. We spent two hours pretending to weigh it evenly.

        She said the thing that scares her isn't leaving, it's finding out she doesn't miss it.

        I didn't say what I was thinking, which is that I'd miss her a lot.
        """, stops: [s(.williamsburg, 1900, 110), s(.dominoPark, 2055, 60)], sky: .clear),
        e(14, .sat, 1600, .brooklynMuseum, """
        An hour in the museum because it was on the way and I had nowhere to be. Sat in front of one painting for most of it. I never do that. I walk past four hundred things and remember none of them.

        One painting, forty minutes. Better deal.
        """, stops: [s(.brooklynMuseum, 1445, 100)]),

        e(13, .tue, 2150, nil, """
        Nothing day. Meetings, a sad salad, laundry. Writing it down anyway, because these are most days and I'd like to remember that they were fine.
        """),
        e(13, .wed, 1240, .unionSquare, """
        # Lunch errand
        Walked down to the Union Square market at lunch for tomatoes and came back with tomatoes, basil, a jar of honey and a plant I have no room for.
        {greenmarket}
        The radish stand looks like a painting every single time.
        """, stops: [s(.unionSquare, 1215, 40)], sky: .partlyCloudy),
        e(13, .sat, 1930, .brooklynBridgePark, """
        Walked down through DUMBO in the late afternoon. The cobblestones were still wet from the street cleaner and the bridge looked fake, like a backdrop someone forgot to roll away.
        {dumbo}
        Then sat on the rocks by the water until the light went.
        {skyline-sunset}
        I complain about this city constantly, and then it does this.
        """, stops: [s(.dumbo, 1745, 40), s(.brooklynBridgePark, 1835, 80)], sky: .mostlyClear),
        e(13, .sun, 1010, .cafe, """
        Sunday pages at the corner table. Notebook for thinking, this for keeping.
        {coffee-notebook}
        Things on my mind, in order of size:
        1. The pitch
        2. Whether Priya is leaving
        3. The noise the fridge is making
        """, stops: [s(.cafe, 940, 70)]),

        e(12, .mon, 2200, nil, """
        # The lease letter
        Renewal came in the mail. Rent goes up $250 in the new term.

        ## Stay
        - The light in the front room
        - Twelve minutes to the park
        - I know the guy at the bodega's kids' names

        ## Go
        - $250
        - The upstairs neighbor's trumpet
        - Four years of the same walls

        Not deciding tonight.
        """),
        e(12, .wed, 2130, .home, """
        Left the office at 8:30. The pitch deck is finally a story and not a pile of screens. Dan found the through line this afternoon: start with the visitor who's lost, not with the museum.

        Tired in the good way.
        """, stops: [s(.office, 910, 685)]),
        e(12, .fri, 1320, .chinatown, """
        # Pitched
        Presented at 11. Forty minutes, six people across the table, one of them smiling the whole time and the other five unreadable. We won't know for a week or more.

        Dan and I walked to Chinatown afterwards and ordered far too much.
        {chinatown-lanterns}
        {chinatown-fruit}
        Whatever happens, I'm proud of what we showed them. Writing that down now, before the result changes how I remember it.
        """, stops: [s(.office, 930, 150), s(.chinatown, 1235, 80)]),
        e(12, .sun, 950, .prospectPark, """
        # Run log
        - 4 miles, the full loop plus a bit
        - Walked the big hill, no shame
        - Legs fine, lungs complaining

        Saw the same older couple who walk the loop holding hands every Sunday. They've lapped my whole personality.
        """, stops: [s(.prospectPark, 840, 75)], sky: .clear),

        e(11, .tue, 1740, .office, """
        # We got it
        Lena called us into the small room at 4 and just said "it's yours." Dan actually jumped. I think I said "okay" about five times.

        The museum project is ours. A year of work, starting next month.

        Going to remember the walk back to my desk for a long time.
        """),
        e(11, .thu, 2245, .home, """
        Film Forum by myself, an old black and white thing with a full house on a Thursday. Somebody behind me laughed half a second before every joke, a person who has clearly seen it thirty times.

        Slice on Carmine after, standing up, the way it's meant to be eaten.
        {pizza}
        """, stops: [s(.filmForum, 1855, 135), s(.carmineStreet, 2120, 25)]),
        e(11, .sat, 1500, .home, """
        # Pasta, attempt two
        More water this time, and I let the dough rest the full half hour instead of pretending ten minutes was thirty.

        It rolled out. It held together. It was **actual pasta**.
        {pasta-bowl}
        Sent a photo to Priya, who replied "who made that for you."
        """),

        e(10, .mon, 745, .home, """
        Up before the alarm. The front room does a thing around seven where the whole wall goes orange for a few minutes.
        {window-sunrise}
        This is the $250.
        """, sky: .clear),
        e(10, .wed, 1825, .pier11, """
        # The long way home
        Took the ferry instead of the train, for no reason except that the sky looked like it deserved it.
        {ferry-window}
        {ferry}
        Costs the same as the subway and feels like a small vacation. Why don't I do this every week? I'll forget by Friday, which is why I'm writing it here.
        """, stops: [s(.pier11, 1810, 20)], sky: .partlyCloudy),
        e(10, .sat, 1950, .home, """
        # Breakneck
        7:50 train from Grand Central with half of Brooklyn and their trail mix. The first mile is basically a ladder made of rock. I stopped pretending I was taking photos and just admitted I needed to breathe.
        {hudson-view}
        The river from the top is absurd. Wide and slow and silver, with a toy train running along the edge.

        Legs are jelly. Fell asleep on the ride back with my head against the window and woke up at 125th.
        """, stops: [s(.grandCentral, 730, 20), s(.breakneckRidge, 920, 260), s(.grandCentral, 1525, 10)], sky: .mostlyClear),

        e(9, .tue, 2215, .home, """
        # Not my best
        Snapped at Dan in the review today. He was right about the navigation, and I didn't want him to be, and I said something sharp about "people who weren't in the research sessions."

        The room went quiet. He let it go, which made it worse.

        I'll say sorry tomorrow, properly, not in passing.
        """),
        e(9, .wed, 925, .office, """
        Found Dan before standup and apologised. He said "I knew you were tired" and bought me a coffee, which is more grace than I'd have managed.

        We're using his navigation.
        """),
        e(9, .fri, 1130, .cafe, """
        Working from the cafe because the trumpet started at nine sharp.
        {coffee-laptop}
        Scales, mostly. Somewhere above me a person is getting better at something, and I'm trying to be a good sport about it.
        """, stops: [s(.cafe, 950, 150)]),
        e(9, .sun, 2030, nil, """
        # Sunday reset
        - [x] Laundry
        - [x] Groceries
        - [x] Call Mom
        - [x] Water the plants
        - [ ] Answer the landlord
        - [ ] Dentist appointment

        The same two never get done.
        """),

        e(8, .mon, 2110, .home, """
        Fell off the blue V4 nine times. The move is a big reach off a bad foot, and I keep hesitating at exactly the moment I can't afford to.

        The woman who sets the routes watched one attempt and said "you're deciding to fall before you fall." Rude. Correct.
        """, stops: [s(.climbingGym, 1830, 100)]),
        e(8, .fri, 1915, .theMet, """
        # Friday night at the Met
        Open late, half empty, the best version of it. I went straight to the American Wing courtyard and sat under the glass while it got dark overhead.
        {met-courtyard}
        {met-stairs}
        Took notes for the museum project and then put the notebook away. Not everything has to be research.
        """, stops: [s(.theMet, 1800, 150)]),
        e(8, .sat, 1420, .carrollGardens, """
        Long lunch with Priya at the red sauce place with the checkered tablecloths. She's made a spreadsheet about Los Angeles. It has a column for "sun" and a column for "people."
        {pasta-plate}
        The people column is all here.
        """, stops: [s(.carrollGardens, 1300, 110)]),

        e(7, .tue, 945, .office, """
        Dentist in Midtown at 8, finally. No cavities and a lecture about flossing delivered with real disappointment.

        Came down through Grand Central after. The platform was nearly empty for once.
        {subway-42nd}
        One box ticked on the Sunday list. Only took five weeks.
        """, stops: [s(.grandCentral, 750, 65)]),
        e(7, .wed, 2200, nil, """
        Two hundred pages into the Caro book. Every chapter makes me look at a different highway with suspicion.

        > Note to self: every road in this city was somebody's decision.

        Reading it in the city it's about is a strange feeling. I walked under one of his overpasses this morning.
        """),
        e(7, .sat, 1100, .home, """
        # Staying
        Signed the lease. Emailed the landlord before I could reopen the question.
        {brownstones}
        What decided it was small. I walked home from the train on Thursday and three separate people said hello, and I realised I'd be paying $250 a month *less* somewhere to know nobody.

        The trumpet stays too, I suppose.
        """),
        e(7, .sun, 1710, .prospectPark, """
        Picnic on the Long Meadow with Dan, his partner and their unreasonable dog. Cheese, a baguette, a frisbee nobody could throw straight.

        Stayed until the grass got cold. Good day. No notes.
        """, stops: [s(.prospectPark, 1430, 180)], sky: .mostlyClear),

        e(6, .mon, 2130, .home, """
        # Rain
        All day, the steady kind. Worked from the couch with the window cracked so I could hear it.
        {rain-fire-escape}
        Made soup, read sixty pages, spoke to no one out loud until the delivery guy at seven.

        > The kind of day that doesn't ask anything of you.
        """, sky: .rain),
        e(6, .thu, 1300, .madisonSquare, """
        Stood in the burger line in the park for twenty five minutes like a tourist. Worth it roughly once a year.
        {flatiron}
        Kickoff for the museum project is Tuesday. I keep waking up at 5 with ideas, which is either excitement or dread. They feel the same at 5.
        """, stops: [s(.madisonSquare, 1225, 50)], sky: .partlyCloudy),
        e(6, .sat, 2240, .home, """
        # Maya's here
        My sister landed at noon and we've been walking since. Bagels, then over the Brooklyn Bridge because she insisted, then back through DUMBO with ice cream.

        She said "you seem settled," which from Maya is a formal commendation.

        She's asleep on the couch now with her shoes still on.
        """, stops: [s(.bagels, 1310, 25), s(.dumbo, 1540, 60), s(.brooklynBridgePark, 1645, 50)], sky: .mostlyClear),
        e(6, .sun, 1900, .home, """
        Took Maya to the market and then the park before her flight. We split a cider donut on a bench and she told me she's thinking of going back to school.

        The apartment is very quiet tonight. Left the couch blanket where she threw it.
        """, stops: [s(.grandArmyPlaza, 1010, 40), s(.prospectPark, 1100, 70)], sky: .partlyCloudy),

        e(5, .tue, 2140, .home, """
        # Kickoff
        Six hours with the museum team. They brought a floor plan the size of a dining table and a volunteer who has given tours for thirty one years and knows where every visitor gets lost.

        Best line of the day, from her: "People don't want to know where they are. They want to know what's near them."

        That's the whole project. I wrote it on the first page of the notebook.
        """),
        e(5, .fri, 2350, .home, """
        Show in Williamsburg with people from work. Small room, loud band, my ears are still ringing a little.

        I'm thirty four and I stood near the back, by choice, next to the exit, also by choice. Had a great time.
        """, stops: [s(.williamsburg, 2000, 170)]),
        e(5, .sun, 1015, .cafe, """
        # Weekly review
        **Went well:** kickoff, two runs, cooked three nights.

        **Didn't:** phone in bed every night, skipped climbing.

        **Next week:**
        - [ ] First sketches to Lena by Thursday
        - [ ] Climb Monday, no excuses
        - [ ] Phone charges in the kitchen
        """, stops: [s(.cafe, 945, 75)]),

        e(4, .mon, 2050, .home, """
        # Sent it
        The blue V4. First try of the night, before I had time to think about it. I didn't decide to fall.

        The route setter gave me a single nod from across the gym. I'd like it framed.
        """, stops: [s(.climbingGym, 1830, 95)]),
        e(4, .wed, 740, .prospectPark, """
        Five miles before work. The park at 6:30 belongs to runners, dog people and one man doing tai chi by the lake who has been there every morning I've ever shown up.

        Ran the hill this time.
        """, stops: [s(.prospectPark, 630, 75)], sky: .clear),
        e(4, .thu, 1920, .brooklynBridgePark, """
        Got off the train two stops early and walked to the pier.
        {skyline-pier}
        Called Maya from the railing. She applied.
        """, stops: [s(.brooklynBridgePark, 1850, 55)], sky: .mostlyClear),
        e(4, .sat, 1400, .home, """
        Repotted everything that needed it. Soil on the floor, on the windowsill, somehow in my hair.
        {window-plants}
        The one I rescued from the market is the only plant that looks happy to be here.
        """),

        e(3, .tue, 2200, nil, """
        First sketches go to the museum tomorrow. I've rearranged the same five screens all evening and they're no better than they were at six.

        Closing the laptop. They're good. Go to bed.
        """),
        e(3, .wed, 1830, .office, """
        # They liked it
        The volunteer guide, the one with thirty one years, tapped the "what's near me" screen and said "I would use this." Then she found a typo in the Egyptian wing.

        Dan and I high fived in the elevator like teenagers.
        """),
        e(3, .fri, 2315, .home, """
        # Dinner for six
        Cacio e pepe for the whole table, made by hand, and it worked. Nobody knew it was only my third time, until I told everyone.

        Priya brought wine and Dan's partner brought a tart from the place on Vanderbilt. We sat at the table until eleven.

        I love this apartment when it's full.
        """),
        e(3, .sun, 1230, .grandArmyPlaza, """
        # Market haul
        - Apples, the tart ones
        - Kale I will feel good about buying
        - Eggs
        - Cheddar from the stand with the samples
        - One cider donut, eaten on site

        Ran into the couple from downstairs and finally learned their names. Four years.
        """, stops: [s(.grandArmyPlaza, 1150, 55)], sky: .clear),

        e(2, .mon, 1330, .home, """
        Went out for coffee at lunch in the rain without an umbrella, on purpose, and didn't hurry.
        {rainy-block}
        The block is at its best wet. Everything goes dark red and shiny.
        """, stops: [s(.cafe, 1245, 25)], sky: .rain),
        e(2, .thu, 2230, .home, """
        # She's going
        Priya took the job. She told me over the phone, quickly, like pulling off a bandage. She leaves in a month.

        I said all the right things and I meant them. It's a great job. She should go.

        Then I sat on the kitchen floor for a while.

        Eleven years of living within three subway stops of each other. I don't know what a week looks like without that in it.
        """),
        e(2, .sat, 1530, .brooklynBridgePark, """
        Lay on the lawn with the Caro book and read maybe nine pages in two hours.
        {brooklyn-bridge-park}
        Mostly watched people. A kid learning to ride a bike fell over four times and got up five.
        """, stops: [s(.brooklynBridgePark, 1340, 135)], sky: .mostlyClear),

        e(1, .mon, 2120, nil, """
        # Three good things
        1. Flashed a V3 I'd never tried
        2. The bodega guy saved me the last everything bagel
        3. Mom sent a photo of the dog asleep in a laundry basket
        """, stops: [s(.climbingGym, 1830, 90)]),
        e(1, .tue, 2205, .home, """
        # Small win
        First working build of the museum map on my phone. It's ugly, it crashes if you rotate it, and it found the Temple of Dendur from the coat check.

        Took forty minutes to fix the bug I'd been avoiding for two weeks. It always takes forty minutes.
        """),
        e(1, .wed, 1255, .madisonSquare, """
        Walked the park loop at lunch. I've been in a low mood since Priya's news and I keep trying to think my way out of it.

        Decided to just be sad about it for a while. It's the correct response.
        """, stops: [s(.madisonSquare, 1235, 35)]),
        e(1, .fri, 2320, .home, """
        Dinner with Priya in Williamsburg, the first since she told me. We made a list of everything she has to do in the city before she goes, and it got to forty items before the food came.

        Number one is the ferry at sunset. Number forty is "cry at JFK."
        """, stops: [s(.williamsburg, 1915, 130), s(.dominoPark, 2130, 35)]),
        e(1, .sat, 1040, .home, """
        # Slow Saturday
        Bagel, paper, a lap of the meadow with coffee.
        {prospect-park-meadow}
        ~~Errands~~ Nothing else planned and no intention of fixing that.
        """, stops: [s(.bagels, 850, 20), s(.prospectPark, 920, 55)], sky: .partlyCloudy),
        e(1, .sun, 2040, nil, """
        Called Mom on the walk back from the park. Told her about Priya and she said "you'll visit, and you'll complain about the driving." Probably right on both.
        {block-dusk}
        Every window on the block was lit by the time I got home.

        ## This week
        - [ ] Second round of sketches
        - [ ] Book flights for the holidays
        - [ ] Start Priya's list
        """),

        e(0, .mon, 740, .home, """
        # Morning pages
        Woke before the alarm. Coffee, the window, ten quiet minutes before the phone.
        {window-mugs}

        Four months of this journal as of this week. I said I wouldn't reread for a month and then never did. Maybe tonight.
        """),
        e(0, .mon, 2135, .home, """
        Reread the whole thing after climbing. The pitch, the lease, Maya on the couch, the V4.

        I'd have told you nothing much happened this year.
        """, stops: [s(.climbingGym, 1830, 90)]),
        e(0, .tue, 2200, .home, """
        Long day, good day. Second round of sketches is half done and Dan thinks the map should open on the visitor, not the building. He's right again. I told him so this time.
        """),
        e(0, .wed, 1300, .madisonSquare, """
        Lunch on the same bench as the first week of this journal. No squirrel, no pretzel. Same twenty minutes, and it still works.
        """, stops: [s(.madisonSquare, 1235, 40)], sky: .mostlyClear),
        e(0, .thu, 2145, .home, """
        # Priya's list, item one
        Ferry from Pier 11, timed for the light. We stood at the back rail the whole way and she didn't take a single photo.

        "I want to just have it," she said.
        """, stops: [s(.pier11, 1810, 20), s(.dumbo, 1845, 75)], sky: .clear),
        e(0, .sat, 1130, .home, """
        Market, bagels, home by eleven. Bought flowers for no reason.
        """, stops: [s(.bagels, 915, 20), s(.grandArmyPlaza, 945, 45)], sky: .mostlyClear),
        e(0, .sun, 2000, .home, """
        # Sunday
        Ran the loop, called Mom, made a pot of soup big enough for the week.

        Quiet, and glad of it.
        """, stops: [s(.prospectPark, 845, 70)], sky: .partlyCloudy),
    ]

    // MARK: - In season only

    static let seasonal: [Seasonal] = [
        inSeason([6, 7, 8], .sat, 1810, .coneyIsland, """
        # Coney Island
        Q train to the end of the line with a towel and a book I didn't open.
        {coney-island-boardwalk}
        {coney-island-beach}
        Hot dog, one ride on the Wonder Wheel in a swinging car I regretted immediately, then an hour in the water. Sunburned in the shape of my tote bag strap.
        """, stops: [s(.coneyIsland, 1250, 330)], sky: .hot),
        inSeason([6, 7, 8], .tue, 2215, .home, """
        # Heat
        The air conditioner gave up at 3 this afternoon, on the hottest day so far. I'm lying on the floor with a bag of frozen peas on my chest, writing this with one hand.

        Someone opened the hydrant on the corner and every kid on the block was in it by 5. Honestly considered it.
        """, sky: .hot),
        inSeason([6, 7, 8], .thu, 2250, .home, """
        Outdoor movie at Brooklyn Bridge Park with a blanket and half the borough. Couldn't hear a word over the helicopters and didn't care. The skyline does the work.

        Walked home through air like soup.
        """, stops: [s(.brooklynBridgePark, 1930, 150)], sky: .mostlyClear),
        inSeason([6, 7, 8], .sun, 815, .prospectPark, """
        Out the door by 6:30 to beat the heat. Four miles, and the park was already full of people with the same idea.

        Iced coffee after, drunk standing in the shade outside the cafe, dripping. A perfect twenty minutes.
        """, stops: [s(.prospectPark, 640, 70), s(.cafe, 800, 30)], sky: .hot),

        inSeason([10, 11], .sun, 1620, .centralPark, """
        # Uptown for the leaves
        Took the train to 72nd and walked the Mall end to end. Every tree is a different yellow, and the path underneath is so thick with leaves that you can't hear your own steps.
        {central-park-mall}
        {central-park-bow-bridge}
        I don't come up here enough. Brooklyn people treat Central Park like a relative we love and never call. But the elms along the Mall do something Prospect Park can't: they close over your head like the ceiling of a church, and for a quarter mile everyone walks a little slower and talks a little lower.

        A saxophone player had set up near the bandshell, working through the same three standards. A man in a very good coat stopped, listened to all of one song with his eyes closed, put a twenty in the case and walked on without a word.

        Kept going down the steps to the terrace and around the lake. A couple in a rowboat were going in slow circles under Bow Bridge and laughing about it. Neither of them could row, and neither of them minded. I watched for longer than was polite.

        Sat on a rock by the water with a coffee from the cart and did nothing for most of an hour. Thought about Priya, who wants to see this before she goes and keeps saying next weekend. Thought about how many falls I've spent meaning to come up here and then looking up to find the branches bare.

        **This year I caught it.** That's all. That's the whole entry.

        Walked out at 59th as the light went gold on the buildings, and took the long train home with leaves in my hood.
        """, stops: [s(.centralPark, 1335, 175)], sky: .mostlyClear),
        inSeason([10, 11], .sat, 1015, .prospectPark, """
        First properly cold run. Gloves, and I could see my breath on the hill.
        {prospect-park-fall}
        The park turned while I wasn't looking. Last week it was green.
        """, stops: [s(.prospectPark, 850, 70)], sky: .clear),
        inSeason([10, 11], .sat, 1940, .home, """
        # Back up the Hudson
        Same early train, different mountain. The colors are at their peak and the whole valley looks like it's been set on fire, gently.
        {hudson-river}
        Ate a sandwich on a rock with my feet hanging over the edge. Didn't check my phone for five hours, mostly because there was no signal, but I'm taking the credit.
        """, stops: [s(.grandCentral, 730, 20), s(.breakneckRidge, 925, 250), s(.grandCentral, 1520, 10)], sky: .clear),
        inSeason([10, 11], .wed, 2145, .home, """
        The radiator came on tonight for the first time, clanking like someone's trapped in it. I'd forgotten the sound and now I'll hear it until April.

        Dark by the time I leave the office now. Bought a ridiculous number of candles.
        """),

        inSeason([12, 1, 2], .sat, 1130, .home, """
        # Snow day
        Six inches overnight and still coming down. The block is silent in a way it never is.
        {snow-street}
        Walked to the park in boots I've owned for three years and worn twice. Kids on sleds, a dog losing its mind with joy, one man on skis.

        Hot chocolate. Not leaving again.
        """, stops: [s(.prospectPark, 930, 70)], sky: .snow),
        inSeason([12, 1, 2], .sun, 1545, .dumbo, """
        Went down to the water to see it in the snow.
        {snow-dumbo}
        Nobody around. My footprints were the only ones on the cobblestones for a whole block, and I felt bad about ruining it.
        """, stops: [s(.dumbo, 1500, 70)], sky: .snow),
        inSeason([12, 1], .thu, 1905, .grandArmyPlaza, """
        Came out of the subway and the arch had its tree up.
        {grand-army-plaza-winter}
        I act above all this every year, and every year I stand here for five minutes anyway.
        """, stops: [s(.grandArmyPlaza, 1855, 20)]),
        inSeason([12, 1, 2], .tue, 2130, .home, """
        Dark at 4:30. Left the office and it already felt like midnight.

        Made the big pot of lentil soup and ate it standing next to the radiator. Winter rules: soup, wool socks, in bed by ten with the Caro book.
        """),

        inSeason([4, 5], .sat, 1245, .botanicGarden, """
        # Cherry blossoms
        The esplanade is at full bloom and so is the crowd, but for once I didn't mind.
        {cherry-blossom-1}
        {cherry-blossom-2}
        Petals coming down like slow snow. A little girl was trying to catch them in a paper cup. I stayed two hours and took a hundred photos of what is basically one tree.
        """, stops: [s(.botanicGarden, 1100, 130)], sky: .mostlyClear),
        inSeason([3, 4], .sun, 1500, .prospectPark, """
        First warm day and the entire neighborhood came outside at once, blinking.
        {prospect-park-meadow}
        The trees haven't caught up yet but the meadow is covered in people. Lay in the grass with my jacket as a pillow until my face got warm.
        """, stops: [s(.prospectPark, 1330, 120)], sky: .clear),
        inSeason([3, 4, 5], .sat, 1700, .home, """
        # Spring cleaning
        Windows open for the first time since October. Washed the curtains, found $12 and a metro card in the couch.

        - [x] Closet
        - [x] Under the bed
        - [ ] The drawer
        """),
        inSeason([3, 4, 5], .wed, 1905, .home, """
        Walked the whole way home over the Manhattan Bridge because it was still light at seven. An hour and a half. My feet hurt and I feel better than I have in weeks.

        Light after work changes everything.
        """),
    ]

    /// Around On This Day: one from a year before the seeding day, one from two years before.
    static let yearAgo = Draft(time: 2110, place: .home, text: """
    # One year in
    A year in this apartment today. I still haven't hung the pictures, and I know which floorboards to step over at night.
    {living-room}

    It's starting to feel like mine.
    """)

    static let twoYearsAgo = Draft(time: 1930, place: .home, text: """
    Moved in. Forty one boxes, three flights, one very patient friend. We ate pizza on the floor because the table is still in pieces.
    {empty-room}

    The front room gets the evening light. That's why I signed.
    """)

    // MARK: - Photos never used in an entry

    static let snapshots: [Snapshot] = [
        Snapshot(week: 15, weekday: .sat, time: 1010, photo: "bagel"),
        Snapshot(week: 13, weekday: .tue, time: 855, photo: "subway-28th"),
        Snapshot(week: 11, weekday: .sun, time: 1035, photo: "coffee-notebook"),
        Snapshot(week: 9, weekday: .sat, time: 1920, photo: "skyline-sunset"),
        Snapshot(week: 8, weekday: .wed, time: 1250, photo: "madison-square-park"),
        Snapshot(week: 5, weekday: .sat, time: 1120, photo: "brownstones"),
        Snapshot(week: 4, weekday: .fri, time: 1045, photo: "coffee-laptop"),
        Snapshot(week: 3, weekday: .sat, time: 1730, photo: "dumbo"),
        Snapshot(week: 2, weekday: .tue, time: 850, photo: "subway-28th"),
        Snapshot(week: 2, weekday: .sun, time: 720, photo: "window-sunrise"),
        Snapshot(week: 1, weekday: .thu, time: 1840, photo: "skyline-pier"),
        Snapshot(week: 0, weekday: .tue, time: 1245, photo: "pizza"),
    ]
}
#endif
