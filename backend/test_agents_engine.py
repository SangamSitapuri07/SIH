import unittest
from unittest.mock import patch

from agents_engine import MultiAgentEngine


class AgentEngineTruthfulnessTests(unittest.TestCase):
    def snapshot(self):
        return {
            'latitude': 18.92,
            'longitude': 72.2,
            'timestamp': 1,
            'variables': {
                'wave_height_m': 1.2,
                'wave_period_s': 6.0,
                'wind_speed_kn': 8.0,
                'wind_gust_kn': 12.0,
                'current_speed_kn': None,
                'chlorophyll_mg_m3': None,
                'sst_celsius': 28.0,
            },
            'sources_used': [
                {'name': 'Open-Meteo Marine'},
                {'name': 'Open-Meteo Forecast'},
            ],
            'sources_failed': [],
            'pfz': [],
        }

    @patch('agents_engine.ollama.generate', return_value=None)
    def test_optional_llm_uses_named_fallback_without_fake_evidence(self, _generate):
        engine = MultiAgentEngine()
        result = engine.run_collaborative_reasoning(self.snapshot())
        by_id = {agent['agent_id']: agent for agent in result['agents']}

        for agent_id in (
            'ocean_analysis', 'satellite_analysis', 'weather_hazard',
            'marine_ecology', 'fisheries_pfz', 'orchestrator',
        ):
            self.assertEqual(by_id[agent_id]['status'], 'fallback')
            self.assertTrue(by_id[agent_id]['fallback_used'])

        self.assertEqual(by_id['anomaly_detection']['status'], 'unavailable')
        serialized = str(result)
        self.assertNotIn('18.2 km offshore', serialized)
        self.assertNotIn('Depth: 42', serialized)
        self.assertNotIn('10-year historical baseline', serialized)
        self.assertNotIn('confidence', serialized)
        self.assertIn('CONDITIONS BELOW CONFIGURED LIMITS', result['headline_en'])
        runtime = {agent['id']: agent for agent in engine.list_agents()}
        self.assertEqual(runtime['ocean_analysis']['provider_state'], 'OLLAMA_NO_VALID_OUTPUT')
        self.assertEqual(runtime['marine_risk']['provider_state'], 'DETERMINISTIC')


if __name__ == '__main__':
    unittest.main()
