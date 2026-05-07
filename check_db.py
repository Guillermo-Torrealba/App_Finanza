import requests
import json
import datetime

url = "https://xycshsxqcfypgffnqmxb.supabase.co/rest/v1/gastos?select=cuenta,item,monto,tipo,categoria,fecha,metodo_pago,estado&order=fecha.desc&limit=10"
headers = {
    "apikey": "sb_publishable_RoIT8jS3qG_VYtX1t--h8A_vqlTyk3_",
    "Authorization": "Bearer sb_publishable_RoIT8jS3qG_VYtX1t--h8A_vqlTyk3_"
}

response = requests.get(url, headers=headers)
data = response.json()
print(json.dumps(data, indent=2, ensure_ascii=False))
