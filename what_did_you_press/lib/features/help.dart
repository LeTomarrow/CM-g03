import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Widget _buildCard(
    String title,
    String content, {
    Color color = AppColors.amber,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 20)),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.danger,
        title: Text('AJUDA'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            _buildCard(
              'A MISSÃO',
              'Tu e o teu parceiro têm de desarmar um engenho explosivo altamente instável. Um de vocês vê a bomba, mas não consegue ler o manual. O outro tem o manual, mas não vê a bomba.',
              color: AppColors.danger,
            ),
            _buildCard(
              'O OPERADOR',
              'O teu ecrã mostra a bomba e os seus módulos. Tens de descrever o que vês ao teu parceiro e seguir as instruções à risca. Um passo em falso e acabou.',
              color: AppColors.amber,
            ),
            _buildCard(
              'O LEITOR DO MANUAL',
              'Tens o manual de desarmamento. Procura depressa as instruções certas a partir do que o operador descreve. Comunica de forma clara e rápida.',
              color: AppColors.neonBlue,
            ),
            _buildCard(
              'COMUNICAÇÃO',
              'Fala. Grita. Faz o que for preciso para passar a informação certa. O tempo está a acabar. "O que é que carregaste?!" podem ser as últimas palavras que ouves.',
              color: AppColors.success,
            ),
            _buildCard(
              'COMO COMEÇAR',
              'No menu, corta Jogar. Um jogador cria a sala e partilha o código de seis dígitos; o outro introduz o código. Antes de começar podem trocar os papéis. O anfitrião inicia quando os dois aparecem como ligados.',
              color: AppColors.neonBlue,
            ),
            _buildCard(
              'OS MÓDULOS',
              'O operador vê Ângulo, Bússola, Morse, Símbolos e Desenho. O leitor consulta as tabelas do manual e guia cada ação. Uma resposta errada dá um strike; três strikes ou tempo a zero fazem a bomba explodir.',
              color: AppColors.neonPurple,
            ),
            _buildCard(
              'HACKERS',
              'Durante a partida podem surgir ataques: ecrã a piscar, vibração contínua ou apagão no manual. Abre o terminal, escreve ajuda/analisar e executa o comando indicado. No apagão, descodifica a senha de César e usa “energia --repor <senha>”.',
              color: AppColors.danger,
            ),
            _buildCard(
              'DESENHO EM DIRETO',
              'No módulo Desenho, o operador desenha dentro da área. O leitor recebe o desenho em direto, compara-o com os símbolos do manual e indica a cor do fio. Limpa e redesenha se necessário antes de confirmar.',
              color: AppColors.neonPurple,
            ),
            _buildCard(
              'SALA E LIGAÇÃO',
              'A sala usa uma ligação direta entre os dois dispositivos. Se alguém sair, a partida termina para o outro jogador e é preciso criar uma nova sala. Mantém ambos os dispositivos ligados à Internet e com a app aberta.',
              color: AppColors.amber,
            ),
          ],
        ),
      ),
    );
  }
}
