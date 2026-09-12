/// Model describing an external data source in the catalog (§5, §11).
class SourceDescriptor {
  final String healthKey;
  final String name;
  final String agency;
  final String host;
  final String authType;
  final String purpose;
  final String defaultNote;

  const SourceDescriptor({
    required this.healthKey,
    required this.name,
    required this.agency,
    required this.host,
    required this.authType,
    required this.purpose,
    required this.defaultNote,
  });
}

/// Authoritative 14-source catalog mapping to /api/v1/health data_sources.
class SourceCatalog {
  static const List<SourceDescriptor> all = <SourceDescriptor>[
    SourceDescriptor(
      healthKey: 'open_meteo_marine',
      name: 'Open-Meteo Marine',
      agency: 'MeteoFrance MFWAM / ECMWF',
      host: 'marine-api.open-meteo.com',
      authType: 'None',
      purpose: 'Hourly wave height, swell period, SST, ocean currents (96h horizon)',
      defaultNote: '96h wave, swell, SST, current live',
    ),
    SourceDescriptor(
      healthKey: 'open_meteo_forecast',
      name: 'Open-Meteo Forecast',
      agency: 'ECMWF IFS',
      host: 'api.open-meteo.com',
      authType: 'None',
      purpose: 'Hourly wind speed, 48h WMO 34kn gale gusts, precipitation',
      defaultNote: 'Hourly wind, gusts, rain live',
    ),
    SourceDescriptor(
      healthKey: 'open_meteo_daily',
      name: 'Open-Meteo Daily',
      agency: 'ECMWF IFS',
      host: 'api.open-meteo.com',
      authType: 'None',
      purpose: 'Daily WMO weather codes and sky conditions',
      defaultNote: 'Daily WMO sky codes',
    ),
    SourceDescriptor(
      healthKey: 'open_meteo_archive',
      name: 'Open-Meteo Archive',
      agency: 'Open-Meteo Historical',
      host: 'archive-api.open-meteo.com',
      authType: 'None',
      purpose: 'Past-year hourly climatology (2024-2025 anomaly baseline)',
      defaultNote: '2024-2025 anomaly baseline active',
    ),
    SourceDescriptor(
      healthKey: 'noaa_coastwatch',
      name: 'NOAA CoastWatch ERDDAP',
      agency: 'US NOAA NESDIS',
      host: 'coastwatch.noaa.gov',
      authType: 'None',
      purpose: 'Satellite chlorophyll-a with today → 3d → 7d DINEOF lag chain',
      defaultNote: 'DINEOF gap-filled chlorophyll live',
    ),
    SourceDescriptor(
      healthKey: 'esa_oc_cci',
      name: 'ESA OC-CCI v6',
      agency: 'European Space Agency',
      host: 'comet.nefsc.noaa.gov',
      authType: 'None',
      purpose: 'Ocean colour cross-validation (labelled cloud-masked in monsoon)',
      defaultNote: 'Monsoon cloud cover blocks optical sensing; NOAA primary used',
    ),
    SourceDescriptor(
      healthKey: 'isro_mosdac',
      name: 'ISRO MOSDAC OCM-3',
      agency: 'ISRO / Space Applications Centre',
      host: 'mosdac.gov.in',
      authType: 'Govt SSO (.env)',
      purpose: 'Oceansat-3 OCM-3 chlorophyll granules with 24s wall-cap protection',
      defaultNote: 'Oceansat-3 OCM-3 granules active',
    ),
    SourceDescriptor(
      healthKey: 'incois_erddap',
      name: 'INCOIS ERDDAP',
      agency: 'MoES / INCOIS Hyderabad',
      host: 'erddap.incois.gov.in',
      authType: 'None',
      purpose: 'Indian Ocean regional oceanographic and biological products',
      defaultNote: 'Indian Ocean regional products synced',
    ),
    SourceDescriptor(
      healthKey: 'incois_las',
      name: 'INCOIS LAS',
      agency: 'INCOIS Live Access Server',
      host: 'las.incois.gov.in',
      authType: 'None',
      purpose: 'SST and ocean parameters fallback (SIGALRM-capped)',
      defaultNote: 'Upstream server slow — honestly labelled; non-blocking fallback',
    ),
    SourceDescriptor(
      healthKey: 'incois_pfz',
      name: 'INCOIS PFZ GeoServer',
      agency: 'MoES / INCOIS Hyderabad',
      host: 'incois.gov.in',
      authType: 'None (WFS)',
      purpose: 'Official daily Potential Fishing Zone line geometry',
      defaultNote: 'Daily Potential Fishing Zone WFS lines loaded',
    ),
    SourceDescriptor(
      healthKey: 'gfw_ais',
      name: 'Global Fishing Watch',
      agency: 'Global Fishing Watch',
      host: 'gateway.api.globalfishingwatch.org',
      authType: 'API Token',
      purpose: 'AIS fishing effort (hours/km²) and fleet density',
      defaultNote: 'AIS fishing effort and fleet density live',
    ),
    SourceDescriptor(
      healthKey: 'jtwc_cyclone',
      name: 'JTWC (US Navy)',
      agency: 'Joint Typhoon Warning Center',
      host: 'www.metoc.navy.mil',
      authType: 'None',
      purpose: 'Active North Indian Ocean tropical cyclone warnings',
      defaultNote: 'Cyclone bulletins active',
    ),
    SourceDescriptor(
      healthKey: 'globe_landmask',
      name: 'GLOBE 1km Land Mask',
      agency: 'NOAA / Local Bundled Raster',
      host: 'local_bundled',
      authType: 'None (Offline)',
      purpose: 'Rhumb line 2km collision check & land-masking chlorophyll',
      defaultNote: '100% offline 1km terrain/coast raster active',
    ),
    SourceDescriptor(
      healthKey: 'nominatim_osm',
      name: 'Nominatim (OSM)',
      agency: 'OpenStreetMap',
      host: 'nominatim.openstreetmap.org',
      authType: 'Polite UA',
      purpose: 'Harbour, coastal village, and landing center search',
      defaultNote: 'Harbour search active',
    ),
  ];

  /// Finds a source descriptor by key.
  static SourceDescriptor? findByKey(String key) {
    for (final s in all) {
      if (s.healthKey.toLowerCase() == key.toLowerCase()) {
        return s;
      }
    }
    return null;
  }
}
