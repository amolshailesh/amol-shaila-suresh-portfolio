pip install ai4bharat-transliteration

pip install pyreadstat

from ai4bharat.transliteration import XlitEngine
import pandas as pd

import pyreadstat
df, meta = pyreadstat.read_dta(r"/content/mz_nrega_.dta", encoding='utf-8')
df["var1"] = df["var1"].astype(str)
df["var2"] = df["var2"].astype(str)
df["var3"] = df["var3"].astype(str)
print(df)

# Function to transliterate a word using XlitEngine and return the first element
def transliterate_sentence(sen):
    e = XlitEngine(src_script_type="indic", beam_width=10)
    out = e.translit_sentence(sen, lang_code="hi")
    if out:
        return out  # Return the first element of the list if it's not empty
    else:
        return None  # Return None if the list is empty

# Apply the function to each row of the "respondent" column
df["transliterated_var1"] = df["var1"].apply(transliterate_sentence)
df["transliterated_var2"] = df["var2"].apply(transliterate_sentence)
df["transliterated_var3"] = df["var3"].apply(transliterate_sentence)

df.to_csv('/content/mz_nrega_transliterated.csv')


from google.colab import files

files.download('/content/mz_nrega_1_transliterated.csv')