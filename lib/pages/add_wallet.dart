import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../main.dart';

class AddWalletPage extends StatefulWidget {
  final Wallet? wallet; // null = add mode, non-null = edit mode
  const AddWalletPage({super.key, this.wallet});

  @override
  State<AddWalletPage> createState() => _AddWalletPageState();
}

class _AddWalletPageState extends State<AddWalletPage> {
  final _nameController = TextEditingController();
  String _selectedIcon = 'wallet';
  int _selectedColor = 0xFF1960A3;

  final List<int> _colorOptions = [
    0xFF1960A3, 0xFF7C3AED, 0xFF059669, 0xFFDC2626,
    0xFFD97706, 0xFF0891B2, 0xFFDB2777, 0xFF65A30D,
    0xFFEA580C, 0xFF4B5563, 0xFFFF8C00, 0xFF0F766E,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.wallet != null) {
      _nameController.text = widget.wallet!.name;
      _selectedIcon = widget.wallet!.iconName;
      _selectedColor = widget.wallet!.colorValue;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama wallet terlebih dahulu')),
      );
      return;
    }

    final newWallet = Wallet(
      id: widget.wallet?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      iconName: _selectedIcon,
      colorValue: _selectedColor,
    );

    final current = List<Wallet>.from(walletsNotifier.value);
    if (widget.wallet != null) {
      final idx = current.indexWhere((w) => w.id == widget.wallet!.id);
      if (idx >= 0) current[idx] = newWallet;
    } else {
      current.add(newWallet);
    }
    walletsNotifier.value = current;
    Navigator.pop(context, true);
  }

  void _delete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Wallet?'),
        content: Text('Wallet "${widget.wallet!.name}" akan dihapus. Transaksi yang ada tidak akan terhapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              final current = List<Wallet>.from(walletsNotifier.value);
              current.removeWhere((w) => w.id == widget.wallet!.id);
              walletsNotifier.value = current;
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBlue = const Color(0xFF002045);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final previewName = _nameController.text.isEmpty ? 'Wallet Name' : _nameController.text;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white : primaryBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.wallet == null ? 'Tambah Wallet' : 'Edit Wallet',
          style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (widget.wallet != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _save,
            child: Text('Simpan',
                style: TextStyle(
                    color: isDark ? Colors.blue.shade200 : const Color(0xFF1960A3),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── PREVIEW CARD ──────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(_selectedColor), Color(_selectedColor).withOpacity(0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Color(_selectedColor).withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(walletIconMap[_selectedIcon] ?? Icons.account_balance_wallet_rounded,
                        color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(previewName,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(currencyNotifier.value + ' 0',
                            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── NAMA WALLET ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nama Wallet',
                      style: TextStyle(color: isDark ? Colors.white : primaryBlue,
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.grey[850] : const Color(0xFFF0F4FA),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      hintText: 'Contoh: Cash, GoPay, BCA, OVO...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.edit_rounded, color: Colors.grey[500], size: 20),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── PILIH IKON ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pilih Ikon',
                      style: TextStyle(color: isDark ? Colors.white : primaryBlue,
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: walletIconMap.entries.map((entry) {
                      final isSelected = _selectedIcon == entry.key;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedIcon = entry.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(_selectedColor)
                                : (isDark ? Colors.grey[800] : const Color(0xFFF0F4FA)),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isSelected
                                ? [BoxShadow(color: Color(_selectedColor).withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 4))]
                                : null,
                          ),
                          child: Icon(entry.value,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              size: 26),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── PILIH WARNA ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pilih Warna',
                      style: TextStyle(color: isDark ? Colors.white : primaryBlue,
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _colorOptions.map((colorVal) {
                      final isSelected = _selectedColor == colorVal;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = colorVal),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: Color(colorVal),
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                            boxShadow: isSelected
                                ? [BoxShadow(color: Color(colorVal).withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]
                                : null,
                          ),
                          child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── SAVE BUTTON ───────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(_selectedColor), Color(_selectedColor).withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Color(_selectedColor).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Simpan Wallet',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
