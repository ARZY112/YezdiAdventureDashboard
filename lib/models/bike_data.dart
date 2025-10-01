class BikeData {
  final int speed;
  final int rpm;
  final int gear;
  final double fuel; // 0.0 to 1.0
  final String mode;
  final bool highBeam;
  final bool hazard;
  final bool engineCheck;
  final bool batteryWarning;
  final double odo;
  final double tripA;
  final double tripB;
  final double dte; // Distance to Empty
  final double afeA; // Average Fuel Economy Trip A
  final double afeB; // Average Fuel Economy Trip B

  BikeData({
    this.speed = 0,
    this.rpm = 0,
    this.gear = 0, // 0 for Neutral
    this.fuel = 0.0,
    this.mode = 'ROAD',
    this.highBeam = false,
    this.hazard = false,
    this.engineCheck = false,
    this.batteryWarning = false,
    this.odo = 0.0,
    this.tripA = 0.0,
    this.tripB = 0.0,
    this.dte = 0.0,
    this.afeA = 0.0,
    this.afeB = 0.0,
  });

  // A factory constructor for a blank state when disconnected.
  static BikeData get blank => BikeData();
}
