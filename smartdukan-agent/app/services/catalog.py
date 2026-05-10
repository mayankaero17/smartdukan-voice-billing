from typing import List, Dict

async def get_catalog(shop_id: str) -> List[Dict]:
    """
    Returns a list of products available in the shop's catalog.
    
    TODO: Replace with Supabase fetch once the database is connected.
    """
    # Sample data for a typical Indian Kirana store
    return [
        {"sku_id": "SKU001", "name": "Aloo", "unit_price": 30.0, "gst_slab": 0, "stock_count": 100},
        {"sku_id": "SKU002", "name": "Pyaaz", "unit_price": 40.0, "gst_slab": 0, "stock_count": 80},
        {"sku_id": "SKU003", "name": "Tamatar", "unit_price": 50.0, "gst_slab": 0, "stock_count": 60},
        {"sku_id": "SKU004", "name": "Maggi Noodles", "unit_price": 14.0, "gst_slab": 12, "stock_count": 50},
        {"sku_id": "SKU005", "name": "Parle-G Biscuit", "unit_price": 10.0, "gst_slab": 12, "stock_count": 100},
        {"sku_id": "SKU006", "name": "Amul Butter", "unit_price": 55.0, "gst_slab": 12, "stock_count": 30},
        {"sku_id": "SKU007", "name": "Tata Salt", "unit_price": 22.0, "gst_slab": 0, "stock_count": 75},
        {"sku_id": "SKU008", "name": "Chini", "unit_price": 45.0, "gst_slab": 5, "stock_count": 90},
        {"sku_id": "SKU009", "name": "Chai Patti", "unit_price": 120.0, "gst_slab": 5, "stock_count": 40},
        {"sku_id": "SKU010", "name": "Atta", "unit_price": 55.0, "gst_slab": 0, "stock_count": 60},
        {"sku_id": "SKU011", "name": "Chawal", "unit_price": 60.0, "gst_slab": 0, "stock_count": 80},
        {"sku_id": "SKU012", "name": "Dal", "unit_price": 100.0, "gst_slab": 0, "stock_count": 50},
        {"sku_id": "SKU013", "name": "Moong Dal", "unit_price": 110.0, "gst_slab": 0, "stock_count": 40},
        {"sku_id": "SKU014", "name": "Sarso Tel", "unit_price": 180.0, "gst_slab": 5, "stock_count": 30},
        {"sku_id": "SKU015", "name": "Doodh", "unit_price": 60.0, "gst_slab": 0, "stock_count": 20},
        {"sku_id": "SKU016", "name": "Bread", "unit_price": 40.0, "gst_slab": 0, "stock_count": 25},
        {"sku_id": "SKU017", "name": "Ande", "unit_price": 8.0, "gst_slab": 0, "stock_count": 120},
        {"sku_id": "SKU018", "name": "Haldi", "unit_price": 15.0, "gst_slab": 5, "stock_count": 60},
        {"sku_id": "SKU019", "name": "Mirchi", "unit_price": 20.0, "gst_slab": 5, "stock_count": 55},
        {"sku_id": "SKU020", "name": "Dhania", "unit_price": 10.0, "gst_slab": 5, "stock_count": 70},
        {"sku_id": "SKU021", "name": "Sabun", "unit_price": 45.0, "gst_slab": 18, "stock_count": 40},
        {"sku_id": "SKU022", "name": "Shampoo", "unit_price": 99.0, "gst_slab": 18, "stock_count": 20},
        {"sku_id": "SKU023", "name": "Biscuit", "unit_price": 20.0, "gst_slab": 12, "stock_count": 60},
        {"sku_id": "SKU024", "name": "Chips", "unit_price": 20.0, "gst_slab": 12, "stock_count": 50},
        {"sku_id": "SKU025", "name": "Cold Drink", "unit_price": 40.0, "gst_slab": 28, "stock_count": 30},
    ]
