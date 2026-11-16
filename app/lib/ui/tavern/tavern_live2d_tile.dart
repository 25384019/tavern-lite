// Tavern Lite: the character page's Live2D tile.
//
// The original imported a model pack and previewed it. No Live2D runtime ships
// here, so the tile draws nothing and the character's sprites carry the stage.

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';

class TavernLive2dTile extends StatelessWidget {
  const TavernLive2dTile({super.key, required this.character});

  final TavernCharacter character;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
