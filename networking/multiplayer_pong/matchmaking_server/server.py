import accelbyte_py_sdk
from accelbyte_py_sdk.core import MyConfigRepository
from accelbyte_py_sdk.services.auth import login_client
from accelbyte_py_sdk.api.ams import fleet_claim_by_keys
from accelbyte_py_sdk.api.ams.models import ApiFleetClaimByKeysReq
import asyncio
from websockets.asyncio.server import serve, broadcast

client_id = ""
client_secret = ""
namespace = "bjorn"
base_url = "https://development.accelbyte.io"

CONNECTIONS = set()


async def register(websocket):
    CONNECTIONS.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        CONNECTIONS.remove(websocket)


async def matchmaker():
    while True:
        while len(CONNECTIONS) >= 2:
            next_two = list(CONNECTIONS)[:2]
            broadcast(next_two, "Match found! Requesting server...")
            host_port = claim()
            if not host_port:
                broadcast(next_two, "No server available. Waiting...")
                break
            broadcast(next_two, host_port)
            await asyncio.sleep(0.1)  # so the message gets sent before closing the connection
            for ws in next_two:
                await ws.close()

        await asyncio.sleep(2)


def claim():
    body = ApiFleetClaimByKeysReq().with_claim_keys(["pong"]).with_regions(["us-west-2"]).with_session_id("none")
    result, err = fleet_claim_by_keys(body=body)
    print(result, err)
    if err:
        return

    host_port = result.ip + ":" + str(result.ports["default"])
    print(host_port)
    return host_port


async def main():
    config = MyConfigRepository(
        base_url=base_url,
        client_id=client_id,
        client_secret=client_secret,
        namespace=namespace,
    )

    accelbyte_py_sdk.initialize(
        options={
            "config": config,
        },
    )

    _, error = login_client()
    if error:
        print(error)
        exit(1)

    async with serve(register, "localhost", 8765):
        await matchmaker()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
