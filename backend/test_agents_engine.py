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
        self.assertTrue(runtime['ocean_analysis']['provider_state'].startswith('OLLAMA_'))
        self.assertEqual(runtime['marine_risk']['provider_state'], 'DETERMINISTIC')

    def test_qwen_role_delimited_output_is_accepted(self):
        text = '\n'.join([
            'ocean_analysis | Ocean finding',
            'satellite_analysis | Satellite finding',
            'weather_hazard | Weather finding',
            'marine_ecology | Ecology finding',
            'fisheries_pfz | PFZ finding',
            'orchestrator | Summary finding',
        ])
        parsed = MultiAgentEngine._parse_analytical_response(text)
        self.assertEqual(len(parsed), 6)
        self.assertEqual(parsed['orchestrator'], 'Summary finding')

    @patch('agents_engine.ollama.generate')
    def test_role_delimited_model_result_completes_all_optional_agents(self, generate):
        generate.return_value = '\n'.join(
            f'{role} | Evidence-bound {role} finding'
            for role in (
                'ocean_analysis', 'satellite_analysis', 'weather_hazard',
                'marine_ecology', 'fisheries_pfz', 'orchestrator',
            )
        )
        result = MultiAgentEngine().run_collaborative_reasoning(self.snapshot())
        optional = [agent for agent in result['agents'] if agent.get('llm_attempted')]
        self.assertEqual(len(optional), 6)
        self.assertTrue(all(agent['status'] == 'completed' for agent in optional))
        self.assertTrue(all(agent['llm_invoked'] for agent in optional))

    @patch('agents_engine.ollama.generate')
    def test_core_advisory_never_waits_for_ollama(self, generate):
        result = MultiAgentEngine().deterministic_advisory(self.snapshot())
        generate.assert_not_called()
        self.assertEqual(result['verdict'], 'GOOD')
        self.assertTrue(all(
            not agent.get('llm_attempted', False)
            for agent in result['agents']
        ))


if __name__ == '__main__':
    unittest.main()
