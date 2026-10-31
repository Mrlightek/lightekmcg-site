import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('routes', Path(__file__).resolve().parents[2] / 'lib/scripts/lightek_mail_route_maps.py')
routes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(routes)


class ReceivingRoutesTest(unittest.TestCase):
    def test_new_mailbox_routes_to_webmail_and_adds_its_domain(self):
        domains, transports = routes.build('hello@new.test lightek\ncare@existing.test lightek\n', 'existing.test OK\nlegacy.test OK\n')
        self.assertEqual('existing.test OK\nlegacy.test OK\nnew.test OK\n', domains)
        self.assertEqual('care@existing.test lightek_mail:\nhello@new.test lightek_mail:\n', transports)
        self.assertNotIn('legacy.test', transports)

    def test_removal_drops_recipient_route_without_removing_other_domain_mail(self):
        _, before = routes.build('first@client.test lightek\nsecond@client.test lightek\n', 'client.test OK\n')
        domains, after = routes.build('second@client.test lightek\n', 'client.test OK\nlegacy.test OK\n')
        self.assertIn('first@client.test', before)
        self.assertNotIn('first@client.test', after)
        self.assertIn('legacy.test OK', domains)

    def test_refuses_empty_maps_catchalls_and_malformed_input(self):
        for recipients in ('', '# no accounts\n', '@client.test lightek', 'client.test lightek', '* lightek', 'hello@client.test lightek extra', 'hello@client.test smtp:evil.test'):
            with self.subTest(recipients=recipients), self.assertRaises(ValueError):
                routes.build(recipients, 'client.test OK')

    def test_deduplicates_and_produces_stable_maps(self):
        source = '# accounts\nb@client.test lightek\na@client.test lightek\nb@client.test lightek\n'
        first = routes.build(source, '# domains\nclient.test OK\n')
        self.assertEqual(first, routes.build(source, first[0]))
        self.assertEqual(2, len(first[1].splitlines()))


if __name__ == '__main__':
    unittest.main()
