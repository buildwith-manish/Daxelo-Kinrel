// lib/features/family/providers/member_detail_provider.dart
//
// DAXELO KINREL — Member Detail Provider
//
// Provides MemberDetailModel with demo data for the Person Detail Screen.
// Includes personal details, relations, timeline events, and notes
// with realistic Indian family member data.

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Data Models ──────────────────────────────────────────────────────

/// Complete detail model for a family member shown on the Person Detail Screen.
class MemberDetailModel {
  const MemberDetailModel({
    required this.memberId,
    required this.name,
    this.nickname,
    this.gender,
    this.dateOfBirth,
    this.birthplace,
    this.currentCity,
    this.phone,
    this.email,
    this.occupation,
    this.bio,
    this.photoUrl,
    this.kinshipNameToUser,
    this.kinshipPathToUser,
    this.generationNumber = 0,
    this.directConnectionsCount = 0,
    this.isDeceased = false,
    this.relations = const [],
    this.timelineEvents = const [],
    this.notes = const [],
  });

  final String memberId;
  final String name;
  final String? nickname;
  final String? gender;
  final String? dateOfBirth;
  final String? birthplace;
  final String? currentCity;
  final String? phone;
  final String? email;
  final String? occupation;
  final String? bio;
  final String? photoUrl;

  /// Kinship name from user to this member (e.g., "चाचा")
  final String? kinshipNameToUser;

  /// Kinship path from user to this member (e.g., "Father → Brother")
  final String? kinshipPathToUser;

  final int generationNumber;
  final int directConnectionsCount;
  final bool isDeceased;

  final List<MemberRelation> relations;
  final List<TimelineEvent> timelineEvents;
  final List<MemberNote> notes;

  /// Computed age from dateOfBirth
  int? get age {
    if (dateOfBirth == null || dateOfBirth!.isEmpty) return null;
    try {
      final dob = DateTime.parse(dateOfBirth!);
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }
}

/// A relation connected to the member.
class MemberRelation {
  const MemberRelation({
    required this.memberId,
    required this.name,
    this.photoUrl,
    this.kinshipName,
    this.gender,
  });

  final String memberId;
  final String name;
  final String? photoUrl;

  /// Kinship name from the current member to this relation (e.g., "बेटा")
  final String? kinshipName;
  final String? gender;
}

/// A timeline event for the member.
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.title,
    required this.date,
    this.description,
    this.eventType = TimelineEventType.milestone,
  });

  final String id;
  final String title;
  final String date;
  final String? description;
  final TimelineEventType eventType;
}

/// Timeline event types.
enum TimelineEventType {
  birth,
  marriage,
  education,
  career,
  milestone,
  travel,
  family,
  memorial,
}

/// A personal note about the member.
class MemberNote {
  const MemberNote({
    required this.id,
    required this.content,
    required this.createdAt,
    this.author = 'You',
  });

  final String id;
  final String content;
  final String createdAt;
  final String author;
}

// ── Provider ──────────────────────────────────────────────────────────

/// Provider that fetches member detail by memberId.
/// Falls back to demo data when Supabase is not available.
final memberDetailProvider =
    FutureProvider.family<MemberDetailModel, String>((ref, memberId) async {
  // In production, this would fetch from Supabase.
  // For now, return demo data.
  return _demoData[memberId] ?? _buildDefaultDemoMember(memberId);
});

// ── Demo Data ─────────────────────────────────────────────────────────

/// Demo members with realistic Indian family details.
final Map<String, MemberDetailModel> _demoData = {
  'member_001': MemberDetailModel(
    memberId: 'member_001',
    name: 'Rajesh Kumar Sharma',
    nickname: 'Raju',
    gender: 'Male',
    dateOfBirth: '1965-03-15',
    birthplace: 'Jaipur, Rajasthan',
    currentCity: 'Delhi',
    phone: '+91 98765 43210',
    email: 'rajesh.sharma@email.com',
    occupation: 'Retired Government Officer',
    bio:
        'Eldest son of the Sharma family. Served in the Railways for 35 years before retiring in 2020. Known for his love of chess and morning walks in Lodhi Garden.',
    kinshipNameToUser: 'चाचा',
    kinshipPathToUser: 'Father → Brother',
    generationNumber: 2,
    directConnectionsCount: 8,
    isDeceased: false,
    relations: [
      MemberRelation(
        memberId: 'member_002',
        name: 'Suresh Kumar Sharma',
        kinshipName: 'पिता (Father)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_003',
        name: 'Kamla Sharma',
        kinshipName: 'माता (Mother)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'member_004',
        name: 'Meena Sharma',
        kinshipName: 'पत्नी (Wife)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'member_005',
        name: 'Vikram Sharma',
        kinshipName: 'बेटा (Son)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_006',
        name: 'Priya Sharma',
        kinshipName: 'बेटी (Daughter)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'member_007',
        name: 'Anil Kumar Sharma',
        kinshipName: 'भाई (Brother)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_008',
        name: 'Ramesh Kumar Sharma',
        kinshipName: 'भाई (Brother)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_009',
        name: 'Sunita Devi',
        kinshipName: 'बहन (Sister)',
        gender: 'Female',
      ),
    ],
    timelineEvents: [
      TimelineEvent(
        id: 'evt_001',
        title: 'Born in Jaipur',
        date: '1965-03-15',
        description: 'Born at SMS Hospital, Jaipur, Rajasthan',
        eventType: TimelineEventType.birth,
      ),
      TimelineEvent(
        id: 'evt_002',
        title: 'Graduated from University of Rajasthan',
        date: '1986-06-20',
        description: 'B.Com from University of Rajasthan, Jaipur',
        eventType: TimelineEventType.education,
      ),
      TimelineEvent(
        id: 'evt_003',
        title: 'Married Meena Joshi',
        date: '1990-02-14',
        description: 'Arranged marriage in Jaipur with traditional ceremonies',
        eventType: TimelineEventType.marriage,
      ),
      TimelineEvent(
        id: 'evt_004',
        title: 'Joined Indian Railways',
        date: '1987-08-01',
        description: 'Started career as Section Officer in Northern Railway',
        eventType: TimelineEventType.career,
      ),
      TimelineEvent(
        id: 'evt_005',
        title: 'Son Vikram born',
        date: '1992-11-08',
        description: 'Born in Safdarjung Hospital, Delhi',
        eventType: TimelineEventType.family,
      ),
      TimelineEvent(
        id: 'evt_006',
        title: 'Daughter Priya born',
        date: '1996-04-22',
        description: 'Born in AIIMS, Delhi',
        eventType: TimelineEventType.family,
      ),
      TimelineEvent(
        id: 'evt_007',
        title: 'Promoted to Senior Divisional Officer',
        date: '2005-01-15',
        description: 'Transferred to Delhi HQ',
        eventType: TimelineEventType.career,
      ),
      TimelineEvent(
        id: 'evt_008',
        title: 'Retired from Indian Railways',
        date: '2020-07-31',
        description:
            'Retired after 33 years of service. Farewell ceremony at Rail Bhavan.',
        eventType: TimelineEventType.milestone,
      ),
    ],
    notes: [
      MemberNote(
        id: 'note_001',
        content:
            'Chachu loves playing chess. He taught me when I was 8 years old. We still play whenever I visit Delhi.',
        createdAt: '2024-01-15',
        author: 'You',
      ),
      MemberNote(
        id: 'note_002',
        content:
            'His pension comes on the 1st of every month. He donates a portion to the local gurudwara.',
        createdAt: '2024-03-20',
        author: 'You',
      ),
      MemberNote(
        id: 'note_003',
        content:
            'Birthday plan: He wants to visit Ranthambore this year for his 60th. Need to book safari in advance.',
        createdAt: '2024-02-28',
        author: 'You',
      ),
    ],
  ),

  'member_007': MemberDetailModel(
    memberId: 'member_007',
    name: 'Anil Kumar Sharma',
    nickname: 'Anil Bhaiya',
    gender: 'Male',
    dateOfBirth: '1970-08-22',
    birthplace: 'Jaipur, Rajasthan',
    currentCity: 'Mumbai',
    phone: '+91 87654 32109',
    email: 'anil.sharma@email.com',
    occupation: 'Chartered Accountant',
    bio:
        'Second son of the Sharma family. Moved to Mumbai in 1995 and built a successful CA practice. Known for his sharp mind and generosity.',
    kinshipNameToUser: 'चाचा',
    kinshipPathToUser: 'Father → Brother',
    generationNumber: 2,
    directConnectionsCount: 6,
    isDeceased: false,
    relations: [
      MemberRelation(
        memberId: 'member_002',
        name: 'Suresh Kumar Sharma',
        kinshipName: 'पिता (Father)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_003',
        name: 'Kamla Sharma',
        kinshipName: 'माता (Mother)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'member_001',
        name: 'Rajesh Kumar Sharma',
        kinshipName: 'भाई (Elder Brother)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_010',
        name: 'Neeta Sharma',
        kinshipName: 'पत्नी (Wife)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'member_011',
        name: 'Rohit Sharma',
        kinshipName: 'बेटा (Son)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_012',
        name: 'Ananya Sharma',
        kinshipName: 'बेटी (Daughter)',
        gender: 'Female',
      ),
    ],
    timelineEvents: [
      TimelineEvent(
        id: 'evt_010',
        title: 'Born in Jaipur',
        date: '1970-08-22',
        eventType: TimelineEventType.birth,
      ),
      TimelineEvent(
        id: 'evt_011',
        title: 'Completed CA',
        date: '1994-05-10',
        description: 'Passed CA final exam on first attempt',
        eventType: TimelineEventType.education,
      ),
      TimelineEvent(
        id: 'evt_012',
        title: 'Married Neeta Agarwal',
        date: '1998-12-05',
        description: 'Wedding in Mumbai with both families present',
        eventType: TimelineEventType.marriage,
      ),
      TimelineEvent(
        id: 'evt_013',
        title: 'Started own CA firm',
        date: '2002-04-01',
        description: 'Sharma & Associates, Andheri West, Mumbai',
        eventType: TimelineEventType.career,
      ),
    ],
    notes: [
      MemberNote(
        id: 'note_010',
        content:
            'Anil Chachu always brings Kaju Katli from Mumbai. His CA firm handles our family\'s tax filing.',
        createdAt: '2024-01-20',
        author: 'You',
      ),
    ],
  ),

  'member_010': MemberDetailModel(
    memberId: 'member_010',
    name: 'Neeta Sharma',
    nickname: 'Neeta Chachi',
    gender: 'Female',
    dateOfBirth: '1973-11-03',
    birthplace: 'Ahmedabad, Gujarat',
    currentCity: 'Mumbai',
    occupation: 'School Teacher',
    bio:
        'Originally from Ahmedabad, married into the Sharma family. Teaches Hindi literature at a CBSE school in Mumbai. Known for her delicious dhokla and handvo.',
    kinshipNameToUser: 'चाची',
    kinshipPathToUser: 'Father → Brother → Wife',
    generationNumber: 2,
    directConnectionsCount: 5,
    isDeceased: false,
    relations: [
      MemberRelation(
        memberId: 'member_007',
        name: 'Anil Kumar Sharma',
        kinshipName: 'पति (Husband)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_011',
        name: 'Rohit Sharma',
        kinshipName: 'बेटा (Son)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_012',
        name: 'Ananya Sharma',
        kinshipName: 'बेटी (Daughter)',
        gender: 'Female',
      ),
    ],
    timelineEvents: [
      TimelineEvent(
        id: 'evt_020',
        title: 'Born in Ahmedabad',
        date: '1973-11-03',
        eventType: TimelineEventType.birth,
      ),
      TimelineEvent(
        id: 'evt_021',
        title: 'Married Anil Sharma',
        date: '1998-12-05',
        eventType: TimelineEventType.marriage,
      ),
      TimelineEvent(
        id: 'evt_022',
        title: 'Joined DAV School as Hindi Teacher',
        date: '2000-07-01',
        eventType: TimelineEventType.career,
      ),
    ],
    notes: [
      MemberNote(
        id: 'note_020',
        content:
            'Neeta Chachi makes the best Gujarati thali. She promised to teach me how to make dhokla next time I visit.',
        createdAt: '2024-04-10',
        author: 'You',
      ),
    ],
  ),

  // Deceased family member example
  'member_002': MemberDetailModel(
    memberId: 'member_002',
    name: 'Suresh Kumar Sharma',
    nickname: 'Babuji',
    gender: 'Male',
    dateOfBirth: '1940-01-10',
    birthplace: 'Jaipur, Rajasthan',
    currentCity: 'Jaipur',
    occupation: 'Retired School Principal',
    bio:
        'Patriarch of the Sharma family. Served as Principal of Government Senior Secondary School, Jaipur for 25 years. A respected figure in the community who always emphasized the importance of education.',
    kinshipNameToUser: 'दादा (Grandfather)',
    kinshipPathToUser: 'Father → Father',
    generationNumber: 1,
    directConnectionsCount: 5,
    isDeceased: true,
    relations: [
      MemberRelation(
        memberId: 'member_003',
        name: 'Kamla Sharma',
        kinshipName: 'पत्नी (Wife)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'member_001',
        name: 'Rajesh Kumar Sharma',
        kinshipName: 'बेटा (Son)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_007',
        name: 'Anil Kumar Sharma',
        kinshipName: 'बेटा (Son)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_008',
        name: 'Ramesh Kumar Sharma',
        kinshipName: 'बेटा (Son)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'member_009',
        name: 'Sunita Devi',
        kinshipName: 'बेटी (Daughter)',
        gender: 'Female',
      ),
    ],
    timelineEvents: [
      TimelineEvent(
        id: 'evt_030',
        title: 'Born in Jaipur',
        date: '1940-01-10',
        eventType: TimelineEventType.birth,
      ),
      TimelineEvent(
        id: 'evt_031',
        title: 'Married Kamla Devi',
        date: '1962-02-20',
        eventType: TimelineEventType.marriage,
      ),
      TimelineEvent(
        id: 'evt_032',
        title: 'Appointed Principal',
        date: '1975-07-01',
        description: 'Government Senior Secondary School, Jaipur',
        eventType: TimelineEventType.career,
      ),
      TimelineEvent(
        id: 'evt_033',
        title: 'Passed away',
        date: '2018-09-14',
        description:
            'Passed away peacefully at home in Jaipur, surrounded by family.',
        eventType: TimelineEventType.memorial,
      ),
    ],
    notes: [
      MemberNote(
        id: 'note_030',
        content:
            'Dadaji was the most respected man in our mohalla. Everyone called him "Sharma Sahab". He used to tutor neighborhood kids for free.',
        createdAt: '2024-02-14',
        author: 'You',
      ),
      MemberNote(
        id: 'note_031',
        content:
            'His death anniversary is on 14th September. The whole family gathers in Jaipur every year for a puja.',
        createdAt: '2024-09-10',
        author: 'You',
      ),
    ],
  ),
};

/// Default demo member for IDs not in the demo data set.
MemberDetailModel _buildDefaultDemoMember(String memberId) {
  return MemberDetailModel(
    memberId: memberId,
    name: 'Family Member',
    nickname: null,
    gender: 'Other',
    dateOfBirth: '1990-01-01',
    birthplace: 'India',
    currentCity: 'India',
    kinshipNameToUser: 'Relative',
    kinshipPathToUser: '—',
    generationNumber: 2,
    directConnectionsCount: 3,
    isDeceased: false,
    relations: [
      MemberRelation(
        memberId: 'rel_001',
        name: 'Related Member 1',
        kinshipName: 'भाई (Brother)',
        gender: 'Male',
      ),
      MemberRelation(
        memberId: 'rel_002',
        name: 'Related Member 2',
        kinshipName: 'बहन (Sister)',
        gender: 'Female',
      ),
      MemberRelation(
        memberId: 'rel_003',
        name: 'Related Member 3',
        kinshipName: 'चचेरा भाई (Cousin)',
        gender: 'Male',
      ),
    ],
    timelineEvents: [
      TimelineEvent(
        id: 'def_evt_001',
        title: 'Born',
        date: '1990-01-01',
        eventType: TimelineEventType.birth,
      ),
    ],
    notes: [],
  );
}
