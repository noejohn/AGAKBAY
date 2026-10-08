class DavaoMountain {
  const DavaoMountain(this.name, this.province);

  final String name;
  final String province;

  String get label => '$name · $province';
}

const davaoMountains = <DavaoMountain>[
  DavaoMountain('Mt. Apo', 'Davao del Sur'),
  DavaoMountain('Mount Dinor', 'Davao del Sur'),
  DavaoMountain('Mount Loay', 'Davao del Sur'),
  DavaoMountain('Viper\'s Peak', 'Davao del Sur'),
  DavaoMountain('Mount Megatong', 'Davao del Norte'),
  DavaoMountain('Mt. Hamiguitan', 'Davao Oriental'),
  DavaoMountain('Mt. Kampalili', 'Davao Oriental'),
  DavaoMountain('Mt. Talomo', 'Davao City'),
];
