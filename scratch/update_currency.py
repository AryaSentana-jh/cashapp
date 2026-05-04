import os

with open('lib/pages/home.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Wrap Scaffold with ValueListenableBuilder
content = content.replace('''return Scaffold(''', '''return ValueListenableBuilder<String>(
      valueListenable: currencyNotifier,
      builder: (context, currencyValue, child) {
        return Scaffold(''')

content = content.replace('''    );
  }
}''', '''    );
      },
    );
  }
}''')

# Replace the peso sign with currencyValue
content = content.replace("'₱", "'''$currencyValue")
content = content.replace("₱", "${currencyValue}")

# The user wants a currency selector in Wallet. 
# Search for My Wallets text and replace it with a Row containing the dropdown.
wallet_title = "Text('My Wallets', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 24, fontWeight: FontWeight.bold))"
dropdown_row = """Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Wallets', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 24, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: isDark ? const Color(0xFF1960A3).withOpacity(0.2) : const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currencyValue,
                    isDense: true,
                    icon: const Icon(Icons.expand_more, size: 16, color: Color(0xFF1960A3)),
                    style: const TextStyle(color: Color(0xFF1960A3), fontSize: 16, fontWeight: FontWeight.bold),
                    dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    items: ['₱', '\\$', '€', '£', '¥', 'Rp'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) { if (val != null) currencyNotifier.value = val; },
                  ),
                ),
              ),
            ],
          )"""

content = content.replace(wallet_title, dropdown_row)

with open('lib/pages/home.dart', 'w', encoding='utf-8') as f:
    f.write(content)
