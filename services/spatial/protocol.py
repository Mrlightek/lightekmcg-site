"""Canonical JSON-schema boundary for network commands and worker IPC."""
import json
from pathlib import Path
from jsonschema import Draft202012Validator

SCHEMA_PATH=Path(__file__).resolve().parents[2]/'config/studio/protocol/spatial-ws-v1.schema.json'
SCHEMA=json.loads(SCHEMA_PATH.read_text())
VALIDATORS={name:Draft202012Validator({'$schema':SCHEMA['$schema'],'$ref':f'#/$defs/{name}','$defs':SCHEMA['$defs']}) for name in SCHEMA['$defs']}
CLIENT_TYPES={'HELLO','CAMERA_UPDATE','TIMELINE_SCRUB','ASSET_TRANSFORM','PING','SDP_OFFER','ICE_CANDIDATE'}

def parse_message(raw,client=True):
    if not isinstance(raw,str) or len(raw.encode())>65536:raise ValueError('Use a JSON message smaller than 64 KiB')
    message=json.loads(raw,parse_constant=lambda value:(_ for _ in ()).throw(ValueError('Numbers must be finite')))
    kind=message.get('type') if isinstance(message,dict) else None
    if kind not in VALIDATORS or (client and kind not in CLIENT_TYPES):raise ValueError('Unsupported message type')
    VALIDATORS[kind].validate(message)
    return message

def durable(message):return message['type'] in {'CAMERA_UPDATE','ASSET_TRANSFORM'} and message['payload']['mode']=='commit'
def preview_key(message):
    payload=message['payload']
    return (message['type'],payload.get('camera_id') or payload.get('object_id') or 'timeline')
