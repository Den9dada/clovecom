// HEX输入格式化器
// 
// 当用户输入HEX字符时，每两个字符后自动添加空格。
// 例如：输入48656C6C6F -> 自动转换为 48 65 6C 6C 6F

import 'package:flutter/services.dart';

/// HEX输入格式化器
/// 
/// 自动在每两个十六进制字符后添加空格
class HexInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 获取新输入的文本
    final newText = newValue.text;
    
    // 如果文本为空，直接返回
    if (newText.isEmpty) {
      return newValue;
    }
    
    // 移除所有空格，只保留十六进制字符
    final cleanText = newText.replaceAll(' ', '').replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    
    // 如果清理后的文本为空，返回空
    if (cleanText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    
    // 在每两个字符后添加空格
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < cleanText.length; i++) {
      if (i > 0 && i % 2 == 0) {
        buffer.write(' ');
      }
      buffer.write(cleanText[i]);
    }
    
    final formattedText = buffer.toString();
    
    // 设置光标位置到末尾
    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
