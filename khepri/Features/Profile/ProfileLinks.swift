import NorthAPI
import SwiftUI

/// A person who opens their profile when tapped; plain when they have no handle.
struct PersonLink: View {
    let person: PublicPerson

    var body: some View {
        if person.handle.isEmpty {
            PersonRow(person: person)
        } else {
            NavigationLink {
                ProfileScreen(handle: person.handle)
            } label: {
                PersonRow(person: person)
            }
        }
    }
}

struct ProfileRoute: Hashable {
    let handle: String
}

struct WorkoutRoute: Hashable {
    let handle: String
    let card: WorkoutCard
    let authorName: String
}
