"""Protocol-faithful local replacement for the Modulate streaming boundary."""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)
app = FastAPI()


def _record(event: dict[str, Any]) -> None:
    state_dir = os.getenv('OMI_STACK_STATE_DIR')
    if not state_dir:
        return
    path = Path(state_dir) / 'modulate.jsonl'
    with path.open('a', encoding='utf-8') as output:
        output.write(json.dumps(event, sort_keys=True) + '\n')


@app.websocket('/api/velma-2-stt-streaming')
async def stream(websocket: WebSocket) -> None:
    await websocket.accept()
    _record({'event': 'connected', 'sample_rate': websocket.query_params.get('sample_rate')})
    sent_segment = False
    try:
        while True:
            message = await websocket.receive()
            if message.get('type') == 'websocket.disconnect':
                return
            data = message.get('bytes')
            if data:
                _record({'event': 'pcm_received', 'bytes': len(data)})
                if not sent_segment:
                    await websocket.send_json(
                        {
                            'type': 'utterance',
                            'utterance': {
                                'text': 'stack transcript',
                                'start_ms': 0,
                                'duration_ms': 100,
                                'speaker': 1,
                            },
                        }
                    )
                    _record({'event': 'segment_sent'})
                    sent_segment = True
            elif message.get('text') == '':
                _record({'event': 'finalize_received'})
                await websocket.send_json({'type': 'done', 'duration_ms': 100})
                return
    except WebSocketDisconnect:
        return
    except Exception:
        logger.exception('listen stack Modulate stub failed')
        raise
