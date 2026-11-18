import base64, hashlib, importlib.util, io, json, pathlib, tarfile, tempfile, unittest
PATH=pathlib.Path(__file__).resolve().parents[2]/'lib/scripts/gatekeeper/pwa_backend_transfer.py'
spec=importlib.util.spec_from_file_location('transfer',PATH);transfer=importlib.util.module_from_spec(spec);spec.loader.exec_module(transfer)
class BackendTransferTest(unittest.TestCase):
    def account_archive(self, extra=None):
        stream=io.BytesIO()
        with tarfile.open(fileobj=stream,mode='w') as archive:
            for name in ['account.json','manifest.json','blobs/member-original'] + ([extra] if extra else []):
                data=b'owned';info=tarfile.TarInfo(name);info.size=len(data);archive.addfile(info,io.BytesIO(data))
        stream.seek(0);return tarfile.open(fileobj=stream)
    def test_account_archive_cannot_include_a_shared_database_queue_or_keys(self):
        with self.account_archive() as archive:self.assertEqual(3,len(transfer.checked_members(archive)))
        for name in ['database.dump','redis.rdb','keys.json','storage/other-original','../other-account']:
            with self.account_archive(name) as archive:
                with self.assertRaises(ValueError):transfer.checked_members(archive)
    def test_shared_account_hold_never_stops_the_database_or_worker(self):
        obj=transfer.Transfer.__new__(transfer.Transfer);obj.shared_source=True
        calls=[]
        obj.rails=lambda action: calls.append(action) or {'status':'frozen' if action=='account_freeze' else 'active','media_bytes':7}
        obj.worker=lambda *_:self.fail('Shared worker must stay online')
        obj.readonly=lambda *_:self.fail('Shared database must stay writable')
        self.assertEqual(7,obj.freeze()['media_bytes']);obj.thaw()
        self.assertEqual(['account_freeze','account_thaw'],calls)
    def test_shared_source_cutover_preserves_runtime_health_and_refuses_reverse_after_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            obj=transfer.Transfer.__new__(transfer.Transfer);obj.state=pathlib.Path(directory);obj.shared_source=True
            obj.c={'domain':'account.example.com','runtime_domain':'runtime.example.com','member_key':'12345678-1234-1234-1234-123456789abc','destination_hostname':'paid.example.com'}
            obj.archive=obj.state/'backend.tar';obj.archive.write_bytes(b'immutable own archive')
            (obj.state/'export.json').write_text(json.dumps({'sha256':transfer.digest(obj.archive)}))
            vhost=obj.state/'account.conf';original='<VirtualHost *:443>\nPassengerAppRoot /opt/shared/current\n</VirtualHost>\n';vhost.write_text(original)
            other=obj.state/'other.conf';other.write_text('other account remains routed here')
            obj.vhost_path=lambda:vhost
            calls=[];obj.run=lambda command:calls.append(command)
            obj.rails=lambda action,**_: {'status':'redirecting'}
            obj.action='redirect';self.assertEqual('redirecting',obj.call()['status'])
            self.assertIn('PassengerAppRoot /opt/shared/current',vhost.read_text())
            self.assertIn('__lightek/',vhost.read_text())
            self.assertIn('https://paid.example.com%{REQUEST_URI}',vhost.read_text())
            self.assertEqual('other account remains routed here',other.read_text())
            self.assertEqual(original,(obj.state/'vhost-before').read_text())
            obj.call();self.assertEqual(1,vhost.read_text().count('ACCOUNT CUTOVER BEGIN'))
            obj.action='rollback_source'
            with self.assertRaisesRegex(ValueError,'reverse transfer'):obj.call()
            self.assertFalse(any('stop' in call for call in calls))
    def archive(self, extra=None):
        stream=io.BytesIO()
        with tarfile.open(fileobj=stream,mode='w') as archive:
            for name in ['database.dump','redis.rdb','keys.json','manifest.json','storage/ab/original.mp4']:
                data=b'kept';info=tarfile.TarInfo(name);info.size=len(data);archive.addfile(info,io.BytesIO(data))
            if extra:archive.addfile(extra,io.BytesIO(b''))
        stream.seek(0);return tarfile.open(fileobj=stream)
    def test_complete_archive_keeps_originals_and_rejects_escape_links_and_unexpected_files(self):
        with self.archive() as archive:self.assertEqual(5,len(transfer.checked_members(archive)))
        for name in ['../outside','/etc/passwd','storage/../../outside','another-secret']:
            with self.archive(tarfile.TarInfo(name)) as archive:
                with self.assertRaises(ValueError):transfer.checked_members(archive)
        for kind in [tarfile.SYMTYPE,tarfile.LNKTYPE]:
            info=tarfile.TarInfo('storage/link');info.type=kind;info.linkname='/etc/shadow'
            with self.archive(info) as archive:
                with self.assertRaises(ValueError):transfer.checked_members(archive)
    def test_oversized_unpacked_content_and_incomplete_archives_are_rejected(self):
        with self.archive() as archive:
            old=transfer.MAX_ARCHIVE;transfer.MAX_ARCHIVE=1
            try:
                with self.assertRaises(ValueError):transfer.checked_members(archive)
            finally:transfer.MAX_ARCHIVE=old
        stream=io.BytesIO()
        with tarfile.open(fileobj=stream,mode='w'):pass
        stream.seek(0)
        with tarfile.open(fileobj=stream) as archive:
            with self.assertRaises(ValueError):transfer.checked_members(archive)
    def test_chunks_resume_identical_bytes_and_reject_corruption_or_wrong_offsets(self):
        with tempfile.TemporaryDirectory() as root:
            obj=transfer.Transfer.__new__(transfer.Transfer);obj.archive=pathlib.Path(root)/'backend.tar';obj.action='write_chunk'
            data=b'original media';obj.c={'offset':0,'data':base64.b64encode(data).decode(),'chunk_sha256':hashlib.sha256(data).hexdigest()}
            self.assertEqual(len(data),obj.call()['copied_bytes']);self.assertEqual(len(data),obj.call()['copied_bytes'])
            obj.c['offset']=len(data)+1
            with self.assertRaises(ValueError):obj.call()
            obj.c['offset']=0;obj.c['data']=base64.b64encode(b'tampered').decode()
            with self.assertRaises(ValueError):obj.call()
            self.assertEqual(data,obj.archive.read_bytes())
    def test_import_cannot_overwrite_destination_after_activation_begins(self):
        with tempfile.TemporaryDirectory() as root:
            obj=transfer.Transfer.__new__(transfer.Transfer);obj.state=pathlib.Path(root);(obj.state/'activation-intent').write_text('1')
            with self.assertRaises(ValueError):obj.apply()
    def test_storage_must_be_the_exact_managed_directory(self):
        with tempfile.TemporaryDirectory() as root:
            obj=transfer.Transfer.__new__(transfer.Transfer);obj.base=pathlib.Path(root);obj.root=obj.base/'current';obj.root.mkdir();(obj.base/'shared/storage').mkdir(parents=True)
            (obj.root/'storage').symlink_to(obj.base/'shared/storage',target_is_directory=True)
            self.assertEqual(obj.base/'shared/storage',obj.storage())
            (obj.root/'storage').unlink();(obj.root/'storage').symlink_to('/etc',target_is_directory=True)
            with self.assertRaises(ValueError):obj.storage()
if __name__=='__main__':unittest.main()
