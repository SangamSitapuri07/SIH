import 'package:flutter/material.dart';
import '../theme/verdict_colors.dart';

/// Classification of agent execution type (§3).
enum AgentClass {
  deterministic,
  llm,
}

/// Descriptor model representing an agent from the authoritative registry.
class AgentDescriptor {
  final String id;
  final String emoji;
  final String name;
  final AgentClass agentClass;
  final String blurb;
  final Color accentColor;
  final List<String> defaultSources;

  const AgentDescriptor({
    required this.id,
    required this.emoji,
    required this.name,
    required this.agentClass,
    required this.blurb,
    required this.accentColor,
    this.defaultSources = const <String>[],
  });

  bool get isDeterministic => agentClass == AgentClass.deterministic;
  bool get isLlm => agentClass == AgentClass.llm;

  String get classLabel => isDeterministic ? 'DETERMINISTIC' : 'LLM AGENT';
}

/// Authoritative 11-agent registry mirroring backend (§3, §11).
class AgentRegistry {
  static const List<AgentDescriptor> all = <AgentDescriptor>[
    AgentDescriptor(
      id: 'data_validation',
      emoji: '✅',
      name: 'Data Validation',
      agentClass: AgentClass.deterministic,
      blurb: 'QC gate: validates physical ranges, missing values, timestamps, and lag chains across all feeds.',
      accentColor: VerdictColors.go,
      defaultSources: <String>['Open-Meteo', 'NOAA', 'INCOIS', 'MOSDAC'],
    ),
    AgentDescriptor(
      id: 'gis_spatial',
      emoji: '🗺️',
      name: 'GIS & Spatial',
      agentClass: AgentClass.deterministic,
      blurb: 'Calculates offshore distance, EEZ zones, maritime boundaries, and nearest safe harbours.',
      accentColor: VerdictColors.info,
      defaultSources: <String>['GLOBE 1km', 'PostGIS', 'INCOIS WFS'],
    ),
    AgentDescriptor(
      id: 'ocean_analysis',
      emoji: '🌊',
      name: 'Ocean Analysis',
      agentClass: AgentClass.llm,
      blurb: 'Analyzes significant wave height, swell period, steepness ratio, currents, and SST gradients.',
      accentColor: VerdictColors.sea,
      defaultSources: <String>['Open-Meteo Marine (MFWAM/ECMWF)'],
    ),
    AgentDescriptor(
      id: 'satellite_analysis',
      emoji: '🛰️',
      name: 'Satellite Analysis',
      agentClass: AgentClass.llm,
      blurb: 'Processes satellite chlorophyll-a and optical colour (ISRO OCM-3 & NOAA CoastWatch).',
      accentColor: Color(0xFF38BDF8),
      defaultSources: <String>['ISRO MOSDAC OCM-3', 'NOAA CoastWatch', 'ESA OC-CCI'],
    ),
    AgentDescriptor(
      id: 'weather_hazard',
      emoji: '🌦️',
      name: 'Weather & Hazard',
      agentClass: AgentClass.llm,
      blurb: 'Tracks tropical storm advisories, WMO 34kn gales, squalls, and lightning hazards.',
      accentColor: VerdictColors.caution,
      defaultSources: <String>['JTWC (US Navy)', 'Open-Meteo Forecast'],
    ),
    AgentDescriptor(
      id: 'map_synoptic',
      emoji: '🗺️',
      name: 'Map Synoptic',
      agentClass: AgentClass.deterministic,
      blurb: 'Generates synoptic pressure fields, isobars, and high/low atmospheric cells.',
      accentColor: Color(0xFF818CF8),
      defaultSources: <String>['ECMWF IFS', 'Open-Meteo'],
    ),
    AgentDescriptor(
      id: 'marine_ecology',
      emoji: '🐟',
      name: 'Marine Ecology',
      agentClass: AgentClass.llm,
      blurb: 'Synthesizes thermal frontal boundaries with chlorophyll to evaluate biological productivity.',
      accentColor: Color(0xFF34D399),
      defaultSources: <String>['NOAA CoastWatch', 'MOSDAC OCM-3', 'INCOIS'],
    ),
    AgentDescriptor(
      id: 'fisheries_pfz',
      emoji: '🎣',
      name: 'Fisheries/PFZ',
      agentClass: AgentClass.llm,
      blurb: 'Interprets official INCOIS Potential Fishing Zones & fleet density for fishing recommendations.',
      accentColor: Color(0xFFA78BFA),
      defaultSources: <String>['INCOIS PFZ GeoServer WFS', 'GFW AIS'],
    ),
    AgentDescriptor(
      id: 'anomaly_detection',
      emoji: '🔍',
      name: 'Anomaly Detection',
      agentClass: AgentClass.deterministic,
      blurb: 'Computes z-scores comparing today conditions against 2024-2025 seasonal climatology.',
      accentColor: Color(0xFFF472B6),
      defaultSources: <String>['Open-Meteo Archive'],
    ),
    AgentDescriptor(
      id: 'marine_risk',
      emoji: '🚨',
      name: 'Marine Risk',
      agentClass: AgentClass.deterministic,
      blurb: 'Executes non-linear worst-case fold across ocean, weather, and land risk to produce verdict.',
      accentColor: VerdictColors.noGo,
      defaultSources: <String>['All Agent Findings'],
    ),
    AgentDescriptor(
      id: 'orchestrator',
      emoji: '🧠',
      name: 'Orchestrator',
      agentClass: AgentClass.llm,
      blurb: 'Coordinates multi-agent waves, resolves dependencies, and synthesizes final skipper advice.',
      accentColor: Color(0xFFF59E0B),
      defaultSources: <String>['ORCA Situation Board'],
    ),
  ];

  /// Finds an agent by its unique ID. If unknown, returns generic fallback descriptor (§3).
  static AgentDescriptor findById(String id) {
    return all.firstWhere(
      (agent) => agent.id.toLowerCase() == id.toLowerCase(),
      orElse: () => AgentDescriptor(
        id: id,
        emoji: '🤖',
        name: _formatAgentName(id),
        agentClass: AgentClass.deterministic,
        blurb: 'Specialized backend agent contributing to ORCA analysis.',
        accentColor: VerdictColors.info,
      ),
    );
  }

  static String _formatAgentName(String id) {
    return id.split('_').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}
