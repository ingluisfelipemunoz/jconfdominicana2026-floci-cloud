"""process-order Lambda.

Triggered by SQS. Each record body is an order document (see
../../events/sample-order.json). The handler writes one item per order into the
DynamoDB `orders` table.

The Floci Lambda runtime injects AWS_ENDPOINT_URL so the boto3 client below
talks back to the local edge endpoint with no extra config.
"""

import json
import os
from decimal import Decimal

import boto3

TABLE_NAME = os.environ.get("ORDERS_TABLE", "orders")

# Floci sets AWS_ENDPOINT_URL in the runtime. When it is absent, .get() returns
# None and boto3 falls back to its own resolution, so this works either way.
_dynamodb = boto3.resource("dynamodb", endpoint_url=os.environ.get("AWS_ENDPOINT_URL"))


def handler(event, context):
    table = _dynamodb.Table(TABLE_NAME)
    written = []

    for record in event.get("Records", []):
        # parse_float=Decimal because DynamoDB rejects native floats.
        order = json.loads(record["body"], parse_float=Decimal)

        if "orderId" not in order:
            print(f"skipping record without orderId: {record.get('messageId')}")
            continue

        table.put_item(Item=order)
        written.append(order["orderId"])
        print(f"wrote order {order['orderId']}")

    return {"written": written, "count": len(written)}
