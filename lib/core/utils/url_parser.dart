class UrlParser {
  static String detectPlatform(String url) {
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('instagram.com') || lowerUrl.contains('instagr.am')) {
      return 'Instagram';
    }
    if (lowerUrl.contains('reddit.com') || lowerUrl.contains('redd.it')) {
      return 'Reddit';
    }
    if (lowerUrl.contains('twitter.com') || lowerUrl.contains('x.com') || lowerUrl.contains('t.co')) {
      return 'Twitter';
    }
    if (lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be')) {
      return 'YouTube';
    }
    if (lowerUrl.contains('tiktok.com')) {
      return 'TikTok';
    }
    if (lowerUrl.contains('t.me') || lowerUrl.contains('telegram.org')) {
      return 'Telegram';
    }
    if (lowerUrl.contains('linkedin.com')) {
      return 'LinkedIn';
    }
    if (lowerUrl.contains('facebook.com') || lowerUrl.contains('fb.com')) {
      return 'Facebook';
    }
    return 'Web';
  }

  static String extractTitle(String url) {
    try {
      final uri = Uri.parse(url);
      final lowerUrl = url.toLowerCase();
      final platform = detectPlatform(url);

      // Platform-specific smart titles
      if (platform == 'YouTube') {
        // youtube.com/watch?v=abc → "YouTube Video"
        // youtu.be/abc → "YouTube Video"
        return 'YouTube Video';
      }

      if (platform == 'Instagram') {
        if (lowerUrl.contains('/reel/')) return 'Instagram Reel';
        if (lowerUrl.contains('/p/')) return 'Instagram Post';
        if (lowerUrl.contains('/stories/')) return 'Instagram Story';
        if (lowerUrl.contains('/tv/')) return 'Instagram Video';
        // instagram.com/username → profile
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.length == 1) return 'Instagram Profile: @${segments[0]}';
        return 'Instagram Post';
      }

      if (platform == 'Reddit') {
        if (lowerUrl.contains('/comments/')) {
          // Extract post title from URL segments
          // reddit.com/r/sub/comments/id/post_title
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 5) {
            final titleSlug = segments[4]
                .replaceAll('_', ' ')
                .replaceAll('-', ' ');
            // capitalize first letter
            return titleSlug.isNotEmpty
                ? titleSlug[0].toUpperCase() + titleSlug.substring(1)
                : 'Reddit Post';
          }
          return 'Reddit Post';
        }
        if (lowerUrl.contains('/r/')) return 'Reddit: r/${uri.pathSegments.where((s) => s.isNotEmpty).elementAtOrNull(1) ?? "community"}';
        return 'Reddit Post';
      }

      if (platform == 'Twitter') {
        if (lowerUrl.contains('/status/')) return 'Tweet';
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.length == 1) return 'Twitter Profile: @${segments[0]}';
        return 'Tweet';
      }

      if (platform == 'TikTok') {
        if (lowerUrl.contains('/video/')) return 'TikTok Video';
        return 'TikTok';
      }

      if (platform == 'LinkedIn') {
        if (lowerUrl.contains('/posts/')) return 'LinkedIn Post';
        if (lowerUrl.contains('/in/')) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final nameIndex = segments.indexOf('in');
          if (nameIndex != -1 && nameIndex + 1 < segments.length) {
            return 'LinkedIn: ${segments[nameIndex + 1].replaceAll('-', ' ')}';
          }
        }
        if (lowerUrl.contains('/article/')) return 'LinkedIn Article';
        return 'LinkedIn';
      }

      if (platform == 'Facebook') {
        if (lowerUrl.contains('/watch/')) return 'Facebook Video';
        if (lowerUrl.contains('/posts/')) return 'Facebook Post';
        return 'Facebook Post';
      }

      if (platform == 'Telegram') {
        return 'Telegram Link';
      }

      // Generic web - try to extract meaningful title from path
      if (uri.pathSegments.isNotEmpty) {
        final lastSegment = uri.pathSegments.last;
        if (lastSegment.isNotEmpty) {
          final cleaned = lastSegment
              .replaceAll(RegExp(r'\.[a-z]+$'), '')  // remove extension
              .replaceAll(RegExp(r'[-_]'), ' ')        // dashes to spaces
              .trim();
          if (cleaned.isNotEmpty) {
            return cleaned[0].toUpperCase() + cleaned.substring(1);
          }
        }
      }

      // Fallback to domain name
      final host = uri.host.replaceAll('www.', '');
      return host.isNotEmpty ? host : 'Web Link';

    } catch (e) {
      return 'Untitled';
    }
  }
}