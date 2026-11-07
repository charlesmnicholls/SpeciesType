/// Settings you can edit. Change names here if your Airtable names are different.
class Config {
  // Same base as BTM.
  static const String baseId = 'apptsFPTXHY0on83K';

  // Table that holds the current species for each barcode (read only).
  static const String speciesTable = 'Basal Dia & DBH';
  static const String speciesTableBarcodeField = 'Barcode';
  static const String speciesTableSpeciesField = 'Species';

  // New table that receives the survey results (write).
  static const String resultsTable = 'Species Check';
  static const String fBarcode = 'Barcode';
  static const String fPlot = 'Plot';
  static const String fRecorded = 'Recorded Species';
  static const String fConfirmed = 'Confirmed Species';
  static const String fStatus = 'Status'; // Confirmed or Changed
  static const String fCheckedAt = 'Checked At';
  static const String fCheckedBy = 'Checked By';

  // Species shown in the drop down. Keep the spelling the same as in Airtable.
  static const List<String> species = [
    'Birch',
    'Alder',
    'Aspen',
    'Rowan',
    'Cherry',
    'Oak',
    'Sitka Spruce',
    'Goat Willow',
  ];
}
