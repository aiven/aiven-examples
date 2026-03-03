import lancedb

db = lancedb.connect(
  uri="db://uri",
  api_key="sk_...",
  region="us-east-1"
)

table = db.open_table("insurance_claims")

table.create_index(
  metric="cosine",
  num_partitions=256,
  num_sub_vectors=96,
  replace=True,
  vector_column="insurance_claim_vector"
)

table.create_fts_index("id")
table.create_fts_index("policy_id")
table.create_fts_index("claim_type")
