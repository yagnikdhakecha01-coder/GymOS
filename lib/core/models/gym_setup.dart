class FitnessGoal {
  final String id;
  final String name;
  final String icon;
  final String color;
  final String description;

  FitnessGoal({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
  });

  factory FitnessGoal.fromJson(Map<String, dynamic> json) {
    return FitnessGoal(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '💪',
      color: json['color'] as String? ?? '0xFF7C3AED',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'description': description,
    };
  }

  FitnessGoal copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    String? description,
  }) {
    return FitnessGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      description: description ?? this.description,
    );
  }
}

class CustomField {
  final String id;
  final String label;
  final String fieldType; // Text, Number, Date, Dropdown, Checkbox, Switch, Paragraph, Photo
  final List<String> options;
  final bool required;
  final bool visible;

  CustomField({
    required this.id,
    required this.label,
    required this.fieldType,
    required this.options,
    this.required = false,
    this.visible = true,
  });

  factory CustomField.fromJson(Map<String, dynamic> json) {
    return CustomField(
      id: json['id'] as String,
      label: json['label'] as String,
      fieldType: json['fieldType'] as String,
      options: List<String>.from(json['options'] as List? ?? []),
      required: json['required'] as bool? ?? false,
      visible: json['visible'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'fieldType': fieldType,
      'options': options,
      'required': required,
      'visible': visible,
    };
  }

  CustomField copyWith({
    String? id,
    String? label,
    String? fieldType,
    List<String>? options,
    bool? required,
    bool? visible,
  }) {
    return CustomField(
      id: id ?? this.id,
      label: label ?? this.label,
      fieldType: fieldType ?? this.fieldType,
      options: options ?? this.options,
      required: required ?? this.required,
      visible: visible ?? this.visible,
    );
  }
}
