import 'package:flutter/material.dart';

enum RuleLanguage {
  en('en', 'English', '🇬🇧'),
  hi('hi', 'हिंदी', '🇮🇳'),
  gu('gu', 'ગુજરાતી', '🇮🇳');

  final String code;
  final String label;
  final String flag;
  const RuleLanguage(this.code, this.label, this.flag);

  static RuleLanguage fromCode(String code) {
    return RuleLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => RuleLanguage.en,
    );
  }
}

class GymRuleItem {
  final String id;
  final IconData icon;
  final String mainRule;
  final List<String> subRules;
  final bool isMandatory;

  const GymRuleItem({
    required this.id,
    required this.icon,
    required this.mainRule,
    required this.subRules,
    this.isMandatory = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'mainRule': mainRule,
    'subRules': subRules,
    'isMandatory': isMandatory,
  };

  factory GymRuleItem.fromMap(Map<String, dynamic> map) => GymRuleItem(
    id: map['id'] ?? '',
    icon: _iconFromId(map['id'] ?? ''),
    mainRule: map['mainRule'] ?? '',
    subRules: List<String>.from(map['subRules'] ?? []),
    isMandatory: map['isMandatory'] ?? true,
  );

  static IconData _iconFromId(String id) {
    switch (id) {
      case 'injury':
        return Icons.health_and_safety_rounded;
      case 'refund':
        return Icons.money_off_rounded;
      case 'transfer':
        return Icons.person_off_rounded;
      case 'equipment':
        return Icons.fitness_center_rounded;
      case 'damage':
        return Icons.broken_image_rounded;
      case 'timing':
        return Icons.access_time_filled_rounded;
      case 'conduct':
        return Icons.gavel_rounded;
      default:
        return Icons.rule_rounded;
    }
  }
}

class MemberAgreementRecord {
  final String id;
  final String gymId;
  final String memberId;
  final String? userId;
  final String memberName;
  final String memberPhone;
  final int rulesVersion;
  final String language;
  final bool agreed;
  final DateTime agreedAt;
  final String? deviceInfo;

  MemberAgreementRecord({
    required this.id,
    required this.gymId,
    required this.memberId,
    this.userId,
    required this.memberName,
    required this.memberPhone,
    required this.rulesVersion,
    required this.language,
    required this.agreed,
    required this.agreedAt,
    this.deviceInfo,
  });

  factory MemberAgreementRecord.fromMap(Map<String, dynamic> map) {
    return MemberAgreementRecord(
      id: map['id']?.toString() ?? '',
      gymId: map['gymId']?.toString() ?? map['gym_id']?.toString() ?? '',
      memberId: map['memberId']?.toString() ?? map['member_id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      memberName: map['member_name']?.toString() ?? map['name']?.toString() ?? 'Member',
      memberPhone: map['member_phone']?.toString() ?? map['phone']?.toString() ?? '',
      rulesVersion: map['rules_version'] is int ? map['rules_version'] : 1,
      language: map['language']?.toString() ?? 'en',
      agreed: map['agreed'] == true,
      agreedAt: map['agreed_at'] != null 
          ? DateTime.tryParse(map['agreed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      deviceInfo: map['device_info']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'gym_id': gymId,
    'member_id': memberId,
    'user_id': userId,
    'member_name': memberName,
    'member_phone': memberPhone,
    'rules_version': rulesVersion,
    'language': language,
    'agreed': agreed,
    'agreed_at': agreedAt.toIso8601String(),
    'device_info': deviceInfo,
  };
}

class DefaultGymRules {
  static const int currentVersion = 1;

  static List<GymRuleItem> getRules(RuleLanguage lang, {List<dynamic>? customRulesData}) {
    if (customRulesData != null && customRulesData.isNotEmpty) {
      try {
        final List<GymRuleItem> customItems = [];
        for (var item in customRulesData) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            String main = map['mainRule_${lang.code}'] ?? map['mainRule'] ?? '';
            List<String> subs = [];
            final rawSubs = map['subRules_${lang.code}'] ?? map['subRules'];
            if (rawSubs is List) {
              subs = rawSubs.map((e) => e.toString()).toList();
            }
            if (main.isNotEmpty) {
              customItems.add(GymRuleItem(
                id: map['id']?.toString() ?? 'custom',
                icon: _iconFromId(map['id']?.toString() ?? ''),
                mainRule: main,
                subRules: subs,
                isMandatory: map['isMandatory'] != false,
              ));
            }
          }
        }
        if (customItems.isNotEmpty) {
          return customItems;
        }
      } catch (_) {}
    }
    switch (lang) {
      case RuleLanguage.hi:
        return _hindiRules;
      case RuleLanguage.gu:
        return _gujaratiRules;
      case RuleLanguage.en:
        return _englishRules;
    }
  }

  static IconData _iconFromId(String id) {
    switch (id) {
      case 'injury':
        return Icons.health_and_safety_rounded;
      case 'refund':
        return Icons.money_off_rounded;
      case 'transfer':
        return Icons.person_off_rounded;
      case 'equipment':
        return Icons.fitness_center_rounded;
      case 'timing':
        return Icons.access_time_filled_rounded;
      case 'damage':
        return Icons.broken_image_rounded;
      case 'conduct':
        return Icons.gavel_rounded;
      default:
        return Icons.verified_user_rounded;
    }
  }


  // ── ENGLISH RULES ──
  static const List<GymRuleItem> _englishRules = [
    GymRuleItem(
      id: 'injury',
      icon: Icons.health_and_safety_rounded,
      mainRule: 'Physical Injury & Health Disclaimer (Gym Not Liable)',
      subRules: [
        'Gym management, trainers, and staff are strictly NOT responsible for any physical injury, muscle tear, medical incident, or accident occurring on the premises.',
        'Members engage in exercise voluntarily and assume full personal responsibility for their health and physical safety.',
        'If you have any prior medical conditions, heart issues, or surgery history, you must consult your doctor and inform gym trainers prior to working out.',
      ],
    ),
    GymRuleItem(
      id: 'refund',
      icon: Icons.money_off_rounded,
      mainRule: 'Strict 100% Non-Refundable Policy',
      subRules: [
        'All fees paid for gym membership, registration, personal training, or packages are strictly 100% NON-REFUNDABLE under any circumstances.',
        'Even if a member attends for only one day, or does not attend a single day after payment, no refund or partial refund will be provided.',
        'No fees will be adjusted against other services or transferred to other months.',
      ],
    ),
    GymRuleItem(
      id: 'transfer',
      icon: Icons.person_off_rounded,
      mainRule: 'Non-Transferable & No Member Replacement',
      subRules: [
        'Gym membership is strictly individual and non-transferable.',
        'No other person, friend, relative, or family member can use the membership in your place.',
        'Member replacement or swapping of registered persons is strictly prohibited. Violating this will lead to immediate cancellation of membership.',
      ],
    ),
    GymRuleItem(
      id: 'equipment',
      icon: Icons.fitness_center_rounded,
      mainRule: 'Gym Equipment Care, Hygiene & Etiquette',
      subRules: [
        'All members must re-rack dumbbells, weight plates, and bars back to their designated holders after each exercise.',
        'Dropping weights, slamming machines, or negligent handling is strictly forbidden. Any damage caused to gym property will be recovered from the member.',
        'Carrying a workout towel and wearing clean indoor athletic shoes is strictly mandatory. Sandal/slippers/barefoot workouts are strictly barred.',
      ],
    ),
    GymRuleItem(
      id: 'timing',
      icon: Icons.access_time_filled_rounded,
      mainRule: 'Shift Timings & Attendance Protocol',
      subRules: [
        'Members must strictly attend during their registered batch/shift hours. Entry outside your chosen shift is not allowed without management approval.',
        'Check-in via the app or front-desk QR code is mandatory upon entering.',
        'Gym workout floor must be vacated promptly at the end of the shift / closing time.',
      ],
    ),
    GymRuleItem(
      id: 'damage',
      icon: Icons.broken_image_rounded,
      mainRule: 'Gym Property & Equipment Damage Liability (100% Cost Recovery)',
      subRules: [
        'Members must handle all gym equipment, machinery, weights, dumbbells, mirrors, and accessories with utmost care.',
        'If any equipment, machine, mirror, or gym property is broken or damaged due to negligence, dropping weights, or mishandling, the member is 100% financially liable and must pay the full replacement or repair cost.',
        'Gym workout floor access and membership may be immediately suspended until all damage costs are fully settled by the member.',
      ],
    ),
    GymRuleItem(
      id: 'conduct',
      icon: Icons.gavel_rounded,
      mainRule: 'Decorum, Discipline & Zero Tolerance Policy',
      subRules: [
        'Harassment, abusive language, loud arguments, or disrespectful behavior towards staff or fellow members will not be tolerated.',
        'Recording unauthorized photos or videos of other gym members without their consent is strictly prohibited.',
        'Gym management reserves the right to immediately terminate the membership of any individual violating decorum without refund.',
      ],
    ),
  ];

  // ── HINDI RULES (हिंदी) ──
  static const List<GymRuleItem> _hindiRules = [
    GymRuleItem(
      id: 'injury',
      icon: Icons.health_and_safety_rounded,
      mainRule: 'शारीरिक चोट और स्वास्थ्य दायित्व (जिम जिम्मेदार नहीं)',
      subRules: [
        'जिम परिसर में वर्कआउट के दौरान होने वाली किसी भी चोट, खिंचाव, दुर्घटना या स्वास्थ्य समस्या के लिए जिम प्रबंधन या ट्रेनर जिम्मेदार नहीं होंगे।',
        'सदस्य अपनी मर्जी और अपनी व्यक्तिगत जिम्मेदारी पर वर्कआउट करते हैं। शारीरिक सुरक्षा की पूरी जिम्मेदारी सदस्य की स्वयं की होगी।',
        'यदि आपको कोई पुरानी बीमारी, दिल की समस्या या सर्जरी हुई है, तो वर्कआउट करने से पहले अपने डॉक्टर से सलाह लें और ट्रेनर को सूचित करें।',
      ],
    ),
    GymRuleItem(
      id: 'refund',
      icon: Icons.money_off_rounded,
      mainRule: 'सख्त नो-रिफंड नीति (फीस वापस नहीं होगी)',
      subRules: [
        'जिम सदस्यता (Membership), रजिस्ट्रेशन या पर्सनल ट्रेनिंग के लिए दी गई फीस किसी भी परिस्थिति में वापस (Non-Refundable) नहीं की जाएगी।',
        'यदि कोई सदस्य केवल एक ही दिन आया हो या फीस भरने के बाद एक भी दिन न आया हो, तब भी कोई फीस वापस नहीं होगी।',
        'फीस को किसी अन्य सेवा में समायोजित (Adjust) या अगले महीनों में ट्रांसफर नहीं किया जाएगा।',
      ],
    ),
    GymRuleItem(
      id: 'transfer',
      icon: Icons.person_off_rounded,
      mainRule: 'सदस्यता अहस्तांतरणीय (मेंबर रिप्लेस नहीं होगा)',
      subRules: [
        'जिम सदस्यता पूरी तरह व्यक्तिगत है और इसे किसी दूसरे व्यक्ति को ट्रांसफर नहीं किया जा सकता।',
        'जिस सदस्य के नाम पर एडमिशन हुआ है, उसके स्थान पर कोई दोस्त, रिश्तेदार या परिवार का सदस्य नहीं आ सकता।',
        'मेंबर बदलना (Replace) पूर्णतः प्रतिबंधित है। नियम उल्लंघन पर सदस्यता तुरंत रद्द कर दी जाएगी।',
      ],
    ),
    GymRuleItem(
      id: 'equipment',
      icon: Icons.fitness_center_rounded,
      mainRule: 'जिम उपकरण सुरक्षा, तौलिया एवं स्वच्छता नियम',
      subRules: [
        'वर्कआउट के बाद डम्बल, प्लेट्स और बारबेल को वापस उनके स्टैंड/जगह पर रखना अनिवार्य है।',
        'वजन को फर्श पर पटकना या मशीनों का गलत इस्तेमाल सख्त मना है। लापरवाही से नुकसान होने पर भरपाई सदस्य को करनी होगी।',
        'वर्कआउट के दौरान अपना तौलिया (Towel) लाना और साफ इंडोर स्पोर्ट्स शूज पहनना अनिवार्य है। चप्पल या नंगे पैर वर्कआउट की अनुमति नहीं है।',
      ],
    ),
    GymRuleItem(
      id: 'timing',
      icon: Icons.access_time_filled_rounded,
      mainRule: 'शिफ्ट समय एवं हाजिरी नियम',
      subRules: [
        'सदस्य को अपने निर्धारित शिफ्ट/समय पर ही आना होगा। बिना अनुमति अन्य शिफ्ट में प्रवेश नहीं मिलेगा।',
        'जिम में प्रवेश करते समय ऐप या रिसेप्शन QR कोड से हाजिरी (Check-in) लगाना अनिवार्य है।',
        'शिफ्ट खत्म होने अथवा जिम बंद होने के समय जिम फ्लोर खाली करना अनिवार्य है।',
      ],
    ),
    GymRuleItem(
      id: 'damage',
      icon: Icons.broken_image_rounded,
      mainRule: 'जिम उपकरण एवं संपत्ति नुकसान भरपाई नियम (100% हर्जाना सदस्य देगा)',
      subRules: [
        'जिम के सभी उपकरण, मशीनें, डम्बल, शीशे और सामग्री का उपयोग पूरी सावधानी और ज़िम्मेदारी के साथ करें।',
        'यदि सदस्य की लापरवाही, वजन पटकने या गलत उपयोग से कोई उपकरण, मशीन या संपत्ति टूटती या खराब होती है, तो उसके पूरे नुकसान/मरम्मत का 100% पैसा सदस्य को ही देना होगा।',
        'नुकसान की पूरी भरपाई न होने तक सदस्य का जिम में प्रवेश तत्काल प्रभाव से रोका जा सकता है।',
      ],
    ),
    GymRuleItem(
      id: 'conduct',
      icon: Icons.gavel_rounded,
      mainRule: 'अनुशासन, आचरण एवं सख्त नियम',
      subRules: [
        'स्टाफ या अन्य सदस्यों के साथ अभद्र भाषा, दुर्व्यवहार या झगड़ा करने पर शून्य सहनशीलता (Zero Tolerance) की नीति है।',
        'अन्य सदस्यों की अनुमति के बिना उनकी फोटो या वीडियो बनाना सख्त मना है।',
        'जिम नियमों का उल्लंघन करने वाले किसी भी सदस्य का एडमिशन बिना किसी रिफंड के तुरंत रद्द करने का अधिकार जिम प्रबंधन के पास सुरक्षित है।',
      ],
    ),
  ];

  // ── GUJARATI RULES (ગુજરાતી) ──
  static const List<GymRuleItem> _gujaratiRules = [
    GymRuleItem(
      id: 'injury',
      icon: Icons.health_and_safety_rounded,
      mainRule: 'શારીરિક ઈજા અને સ્વાસ્થ્ય જવાબદારી (જિમ જવાબદાર રહેશે નહીં)',
      subRules: [
        'જિમમાં કસરત દરમિયાન થતી કોઈપણ શારીરિક ઈજા, સ્નાયુ ખેંચાણ, તબીબી સમસ્યા કે અકસ્માત માટે જિમ સંચાલક કે ટ્રેનર જવાબદાર રહેશે નહીં.',
        'દરેક સભ્ય પોતાની સ્વેચ્છાએ અને પોતાના જોખમે કસરત કરે છે. પોતાની શારીરિક સલામતીની સંપૂર્ણ જવાબદારી સભ્યની પોતાની રહેશે.',
        'જો તમને કોઈ જૂની બીમારી, હૃદયની સમસ્યા કે સર્જરી હોય, તો વર્કઆઉટ શરૂ કરતાં પહેલાં તમારા ડૉક્ટરની સલાહ લેવી અને ટ્રેનરને જાણ કરવી ફરજિયાત છે.',
      ],
    ),
    GymRuleItem(
      id: 'refund',
      icon: Icons.money_off_rounded,
      mainRule: 'ફી પરત નહીં મળવાની કડક નીતિ (No Refund Policy)',
      subRules: [
        'જિમ મેમ્બરશીપ, એડમિશન કે પર્સનલ ટ્રેનિંગ માટે ભરેલી કોઈપણ ફી કોઈપણ સંજોગોમાં પરત (Non-Refundable) મળશે નહીં.',
        'જો સભ્ય માત્ર એક જ દિવસ આવ્યો હોય અથવા ફી ભર્યા પછી એક પણ દિવસ ન આવ્યો હોય, તો પણ ફી પરત મળશે નહીં.',
        'ભરેલી ફી અન્ય કોઈ સેવા સામે એડજસ્ટ થશે નહીં કે આગળના મહિનાઓમાં ટ્રાન્સફર થશે નહીં.',
      ],
    ),
    GymRuleItem(
      id: 'transfer',
      icon: Icons.person_off_rounded,
      mainRule: 'મેમ્બરશીપ ટ્રાન્સફર કે બદલી થશે નહીં (No Replacement)',
      subRules: [
        'જિમ મેમ્બરશીપ સંપૂર્ણપણે વ્યક્તિગત છે અને અન્ય કોઈ વ્યક્તિને ટ્રાન્સફર થઈ શકશે નહીં.',
        'જે સભ્યનું રજીસ્ટ્રેશન થયું હોય તેની જગ્યાએ તેના મિત્ર, સગા કે પરિવારના અન્ય સભ્ય આવી શકશે નહીં.',
        'સભ્યની જગ્યાએ અન્ય કોઈને મોકલવાની સખત મનાઈ છે. આ નિયમનો ભંગ થતાં મેમ્બરશીપ તાત્કાલિક રદ કરવામાં આવશે.',
      ],
    ),
    GymRuleItem(
      id: 'equipment',
      icon: Icons.fitness_center_rounded,
      mainRule: 'સાધનોની કાળજી, નેપકીન અને સ્વચ્છતાના નિયમો',
      subRules: [
        'કસરત કર્યા પછી ડમ્બેલ, વજન પ્લેટો અને બારબેલને યોગ્ય સ્ટેન્ડ પર પાછા મૂકવા ફરજિયાત છે.',
        'વજનને જમીન પર પછાડવું કે મશીનોનો દુરુપયોગ કરવો સખત મનાઈ છે. બેદરકારીથી થયેલા નુકસાનની ભરપાઈ સભ્યએ કરવી પડશે.',
        'જિમમાં વર્કઆઉટ નેપકીન/ટુવાલ લાવવો અને સ્વચ્છ ઇનડોર સ્પોર્ટ્સ શૂઝ પહેરવા ફરજિયાત છે. ચંપલ કે ખુલ્લા પગે કસરત કરવાની પરવાનગી નથી.',
      ],
    ),
    GymRuleItem(
      id: 'timing',
      icon: Icons.access_time_filled_rounded,
      mainRule: 'સમયપત્રક અને હાજરીના નિયમો',
      subRules: [
        'સભ્યએ પોતાને ફાળવેલા સમય (શિફ્ટ) દરમિયાન જ આવવાનું રહેશે. સંચાલકની પૂર્વ મંજૂરી વગર અન્ય શિફ્ટમાં પ્રવેશ મળશે નહીં.',
        'જિમમાં પ્રવેશ કરતી વખતે એપ અથવા રિસેપ્શન QR કોડ સ્કેન કરી હાજરી પૂરવી ફરજિયાત છે.',
        'શિફ્ટ પૂર્ણ થતાં જિમ ફ્લોર ખાલી કરવું આવશ્યક છે.',
      ],
    ),
    GymRuleItem(
      id: 'damage',
      icon: Icons.broken_image_rounded,
      mainRule: 'જિમ સાધન અને મિલકત નુકસાની ભરપાઈનો નિયમ (૧૦૦% નુકસાન ખર્ચ સભ્યએ ચૂકવવો પડશે)',
      subRules: [
        'જિમના તમામ સાધનો, મશીનરી, વજન, અરીસા અને સામગ્રીનો ઉપયોગ અત્યંત કાળજીપૂર્વક કરવો ફરજિયાત છે.',
        'સભ્યની બેદરકારી, વજન પછાડવાથી કે ગેરવર્તનથી જિમના કોઈપણ સાધન કે મિલકતને નુકસાન થશે, તો તેનું ૧૦૦% રિપેરિંગ અથવા નવું સાધન લાવવાનો તમામ ખર્ચ સભ્યએ જ ચૂકવવો પડશે.',
        'નુકસાનીની સંપૂર્ણ ભરપાઈ ન થાય ત્યાં સુધી જિમમાં પ્રવેશ તાત્કાલિક સ્થગિત કરવામાં આવી શકે છે.',
      ],
    ),
    GymRuleItem(
      id: 'conduct',
      icon: Icons.gavel_rounded,
      mainRule: 'શિસ્ત, સભ્યતા અને કડક શિસ્તભંગ નીતિ',
      subRules: [
        'સ્ટાફ કે અન્ય સભ્યો સાથે ગેરવર્તણૂક, અપશબ્દો કે ઝઘડો કરનાર સામે સખત પગલાં લેવામાં આવશે.',
        'અન્ય સભ્યોની પરવાનગી વગર ફોટોગ્રાફી કે વિડીયો શૂટિંગ કરવાની સખત મનાઈ છે.',
        'જિમના નિયમો અને શિસ્તનો ભંગ કરનાર સભ્યનું એડમિશન કોઈપણ ફી પરત કર્યા વગર રદ કરવાનો અધિકાર સંચાલક પાસે સુરક્ષિત છે.',
      ],
    ),
  ];

  static Map<String, String> getLabels(RuleLanguage lang, {String? gymName}) {
    final String gName = (gymName != null &&
            gymName.trim().isNotEmpty &&
            gymName.trim().toUpperCase() != 'GYMOS')
        ? gymName.trim()
        : '';
    switch (lang) {
      case RuleLanguage.hi:
        final displayGym = gName.isNotEmpty ? gName : 'जिम';
        return {
          'title': '$displayGym - नियम एवं सदस्यता अनुबंध',
          'subtitle': 'आगे बढ़ने से पहले कृपया $displayGym के सभी नियमों को ध्यान से पढ़ें और स्वीकार करें',
          'selectLanguage': 'भाषा चुनें',
          'mainRule': 'मुख्य नियम',
          'subRules': 'विवरण',
          'chkRead': 'मैंने $displayGym के उपरोक्त सभी नियमों, शर्तों एवं सुरक्षा दिशा-निर्देशों को ध्यानपूर्वक पढ़ लिया है।',
          'chkAgree': 'मैं बिना किसी विवाद के $displayGym के इन सभी नियमों और नीतियों का पालन करने के लिए सहमत हूँ।',
          'btnAccept': '$displayGym के नियम स्वीकार करें और प्रवेश करें',
          'btnLogout': 'अस्वीकार करें एवं लॉगआउट करें',
          'agreedBadge': 'नियम स्वीकृत',
          'pendingBadge': 'नियम स्वीकृति लंबित',
          'agreedOn': 'स्वीकृति दिनांक',
          'mustCheckBoth': 'कृपया आगे बढ़ने के लिए दोनों चेकबॉक्स पर टिक करें',
          'acceptedSuccess': '$displayGym के नियम सफलतापूर्वक स्वीकार किए गए!',
        };
      case RuleLanguage.gu:
        final displayGym = gName.isNotEmpty ? gName : 'જિમ';
        return {
          'title': '$displayGym - નિયમો અને સભ્યતા કરાર',
          'subtitle': 'આગળ વધતા પહેલાં કૃપા કરીને $displayGym ના બધા નિયમો ધ્યાનથી વાંચો અને સ્વીકારો',
          'selectLanguage': 'ભાષા પસંદ કરો',
          'mainRule': 'મુખ્ય નિયમ',
          'subRules': 'વિગત',
          'chkRead': 'મેં $displayGym ના ઉપર જણાવેલા તમામ નિયમો, શરતો અને સલામતી માર્ગદર્શિકા ધ્યાનપૂર્વક વાંચી લીધા છે.',
          'chkAgree': 'હું કોઈપણ વિવાદ વગર $displayGym ના આ તમામ નિયમો અને નીતિઓનું પાલન કરવા સંમત છું.',
          'btnAccept': '$displayGym ના નિયમો સ્વીકારો અને પ્રવેશ કરો',
          'btnLogout': 'અસ્વીકાર કરો અને લૉગઆઉટ કરો',
          'agreedBadge': 'નિયમો સ્વીકારેલ છે',
          'pendingBadge': 'નિયમ સ્વીકૃતિ બાકી',
          'agreedOn': 'સ્વીકૃતિ તારીખ',
          'mustCheckBoth': 'કૃપા કરીને આગળ વધવા બંને ચેકબોક્સ પર ક્લિક કરો',
          'acceptedSuccess': '$displayGym ના નિયમો સફળતાપૂર્વક સ્વીકારવામાં આવ્યા!',
        };
      case RuleLanguage.en:
        final displayGym = gName.isNotEmpty ? gName : 'Gym';
        return {
          'title': '$displayGym - Rules & Membership Agreement',
          'subtitle': 'Please carefully review and accept $displayGym rules and policies before accessing the app',
          'selectLanguage': 'Select Language',
          'mainRule': 'Main Rule',
          'subRules': 'Sub-rules',
          'chkRead': 'I have carefully read and understood all the rules and policies of $displayGym.',
          'chkAgree': 'I agree to strictly abide by all rules, terms, and safety policies of $displayGym without dispute.',
          'btnAccept': 'Accept $displayGym Rules & Enter',
          'btnLogout': 'Decline & Logout',
          'agreedBadge': 'Rules Agreed',
          'pendingBadge': 'Agreement Pending',
          'agreedOn': 'Agreed On',
          'mustCheckBoth': 'Please check both boxes to agree and continue',
          'acceptedSuccess': '$displayGym rules agreed successfully!',
        };
    }
  }
}
