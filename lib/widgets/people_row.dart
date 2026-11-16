import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/search_results.dart';
import '../theme/app_theme.dart';
import 'media_row.dart';
import 'ui.dart';

/// Rangée de personnes (acteurs, réalisateurs) : photo ronde (ou
/// initiales), nom, et le rôle s'il est connu.
class PeopleRow extends StatelessWidget {
  const PeopleRow({
    super.key,
    required this.api,
    required this.title,
    required this.people,
    required this.onOpen,
  });

  final JellyfinApi api;
  final String title;
  final List<SearchPerson> people;
  final ValueChanged<SearchPerson> onOpen;

  static const _size = 84.0;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final textTheme = Theme.of(context).textTheme;
    // Une ligne de plus sous les noms quand des rôles sont connus
    final hasRoles = people.any((person) => person.role != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _size + (hasRoles ? 66 : 48),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            clipBehavior: Clip.none,
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final person = people[index];
              final url = api.imageUrl(
                itemId: person.id,
                type: 'Primary',
                tag: person.imageTag,
                width: 240,
              );
              final initials = Center(
                child: Text(
                  person.initials,
                  style: textTheme.titleLarge?.copyWith(color: AppColors.grey),
                ),
              );
              return PressableScale(
                onTap: () => onOpen(person),
                child: SizedBox(
                  width: _size,
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: _size,
                          child: ColoredBox(
                            color: AppColors.surface3,
                            child: url == null
                                ? initials
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 240,
                                    placeholder: (_, _) => initials,
                                    errorWidget: (_, _, _) => initials,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        person.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (person.role case final role?)
                        Text(
                          role,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.grey,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
