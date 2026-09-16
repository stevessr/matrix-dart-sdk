// SPDX-FileCopyrightText: 2026 stevessr
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/src/utils/markdown.dart';
import 'package:test/test.dart';

void main() {
  group('complex inline LaTeX', () {
    test('keeps escaped dollars inside one math node', () {
      expect(
        markdown(r'cost $\text{price \$5}$'),
        r'cost <span data-mx-maths="\text{price \$5}"><code>\text{price \$5}</code></span>',
      );
    });

    test('handles nested complex TeX without changing the payload', () {
      const latex =
          r'\left(\sum_{i=1}^{n}\frac{x_i^2}{\sqrt{1+x_i^2}}\right)';
      expect(
        markdown('value \$$latex\$'),
        'value <span data-mx-maths="$latex"><code>$latex</code></span>',
      );
    });

    test('recognizes adjacent independent formulas', () {
      expect(
        markdown(r'$a_1$ and $b_2$'),
        r'<span data-mx-maths="a_1"><code>a_1</code></span> and <span data-mx-maths="b_2"><code>b_2</code></span>',
      );
    });

    test('does not turn whitespace-delimited currency-like text into math', () {
      expect(markdown(r'$5 and $6'), r'$5 and $6');
    });
  });
}
