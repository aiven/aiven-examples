"""
Query LanceDB to search and retrieve Kafka messages.

This utility script demonstrates how to query messages stored in LanceDB.
"""

import os
import json
import lancedb
import pandas as pd
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def connect_to_lancedb(db_path: str, table_name: str):
    """
    Connect to LanceDB and open the table.
    
    Args:
        db_path: Path to LanceDB database
        table_name: Name of the table
    
    Returns:
        LanceDB table instance
    """
    try:
        db = lancedb.connect(db_path)
        table = db.open_table(table_name)
        logger.info(f"Connected to LanceDB table '{table_name}'")
        return table
    except Exception as e:
        logger.error(f"Failed to connect to LanceDB: {e}")
        raise


def search_by_vector(table, query_vector, limit=10, filters=None):
    """
    Search for similar vectors in LanceDB.
    
    Args:
        table: LanceDB table instance
        query_vector: Query vector for similarity search
        limit: Maximum number of results
        filters: Optional SQL filter string
    
    Returns:
        pandas DataFrame with results
    """
    query = table.search(query_vector).limit(limit)
    
    if filters:
        query = query.where(filters)
    
    results = query.to_pandas()
    return results


def get_all_messages(table, limit=100):
    """
    Get all messages from the table (limited).
    
    Args:
        table: LanceDB table instance
        limit: Maximum number of results
    
    Returns:
        pandas DataFrame with results
    """
    # LanceDB doesn't have a direct "select all", so we use search with a zero vector
    # or we can use table.to_pandas() if available
    try:
        # Try to get all data
        df = table.to_pandas()
        return df.head(limit)
    except Exception:
        # Fallback: use search with a dummy vector
        dummy_vector = [0.0] * 128  # Adjust dimension as needed
        return search_by_vector(table, dummy_vector, limit=limit)


def filter_by_category(table, category: str, limit=10):
    """
    Filter messages by category.
    
    Args:
        table: LanceDB table instance
        category: Category to filter by
        limit: Maximum number of results
    
    Returns:
        pandas DataFrame with results
    """
    # Use a dummy vector for the search, but filter by category
    dummy_vector = [0.0] * 128
    filters = f"category = '{category}'"
    return search_by_vector(table, dummy_vector, limit=limit, filters=filters)


def display_results(results: pd.DataFrame):
    """
    Display search results in a readable format.
    
    Args:
        results: pandas DataFrame with results
    """
    if results.empty:
        print("No results found.")
        return
    
    print(f"\nFound {len(results)} results:\n")
    print("=" * 80)
    
    for idx, row in results.iterrows():
        print(f"\nResult {idx + 1}:")
        print(f"  ID: {row.get('id', 'N/A')}")
        print(f"  Message: {row.get('message', 'N/A')}")
        print(f"  Timestamp: {row.get('timestamp', 'N/A')}")
        print(f"  Category: {row.get('category', 'N/A')}")
        print(f"  Value: {row.get('value', 'N/A')}")
        print(f"  Kafka Offset: {row.get('kafka_offset', 'N/A')}")
        print(f"  Kafka Partition: {row.get('kafka_partition', 'N/A')}")
        
        # Display raw data if available
        if 'raw_data' in row and pd.notna(row['raw_data']):
            try:
                raw_data = json.loads(row['raw_data'])
                print(f"  Raw Data: {json.dumps(raw_data, indent=4)}")
            except:
                print(f"  Raw Data: {row['raw_data']}")
        
        print("-" * 80)


def main():
    """Main function to demonstrate querying LanceDB."""
    db_path = os.environ.get("LANCEDB_PATH", "./lancedb_data")
    table_name = os.environ.get("LANCEDB_TABLE_NAME", "kafka_messages")
    
    try:
        table = connect_to_lancedb(db_path, table_name)
        
        # Example 1: Get all messages
        print("\n=== Example 1: Get All Messages ===")
        all_messages = get_all_messages(table, limit=5)
        display_results(all_messages)
        
        # Example 2: Search by vector similarity
        print("\n=== Example 2: Vector Similarity Search ===")
        # Create a sample query vector (adjust dimension as needed)
        query_vector = [0.1] * 128
        similar_results = search_by_vector(table, query_vector, limit=5)
        display_results(similar_results)
        
        # Example 3: Filter by category
        print("\n=== Example 3: Filter by Category ===")
        category_results = filter_by_category(table, "category_0", limit=5)
        display_results(category_results)
        
        # Example 4: Get table statistics
        print("\n=== Example 4: Table Statistics ===")
        try:
            df = table.to_pandas()
            print(f"Total messages: {len(df)}")
            if 'category' in df.columns:
                print(f"\nMessages by category:")
                print(df['category'].value_counts())
            if 'kafka_partition' in df.columns:
                print(f"\nMessages by partition:")
                print(df['kafka_partition'].value_counts())
        except Exception as e:
            logger.warning(f"Could not get statistics: {e}")
        
    except Exception as e:
        logger.error(f"Query failed: {e}")
        raise


if __name__ == "__main__":
    main()
