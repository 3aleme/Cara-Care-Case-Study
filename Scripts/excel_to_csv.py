import pandas as pd
from pathlib import Path

root = Path(__file__).parent.parent
df = pd.read_excel(root / 'Case Study' / 'cara-care-raw-patient-touchpoints__4_.xlsx')
df.to_csv(root / 'patient_touchpoints' / 'seeds' / 'raw_patient_touchpoints.csv', index=False)
print(f'Done. Rows: {len(df)}')
