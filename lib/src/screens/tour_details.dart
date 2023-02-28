import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opentourguide/src/download_manager.dart';

import '../models/data.dart';
import '../widgets/details_description.dart';
import '../widgets/details_header.dart';
import '../widgets/details_screen_header_delegate.dart';
import '../widgets/waypoint_card.dart';
import 'navigation/navigation.dart';

class TourDetails extends StatefulWidget {
  const TourDetails(this.tour, {super.key});

  final TourModel tour;

  @override
  State<TourDetails> createState() => _TourDetailsState();
}

class _TourDetailsState extends State<TourDetails>
    with SingleTickerProviderStateMixin {
  bool _isFullyDownloaded = false;

  @override
  void initState() {
    super.initState();

    widget.tour
        .isFullyDownloaded()
        .then((value) => setState(() => _isFullyDownloaded = value));
  }

  @override
  Widget build(BuildContext context) {
    Widget action;
    if (_isFullyDownloaded) {
      action = ElevatedButton(
        onPressed: () {
          Navigator.of(context).push(NavigationRoute(widget.tour));
        },
        style: const ButtonStyle(
            padding: MaterialStatePropertyAll(EdgeInsets.zero),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12.0)),
              ),
            )),
        child: Row(
          children: const [
            SizedBox(width: 12.0),
            Icon(Icons.explore),
            SizedBox(width: 8.0),
            Text("Start"),
            SizedBox(width: 12.0),
          ],
        ),
      );
    } else {
      action = _DownloadButton(
        tour: widget.tour,
        onDownloaded: () {
          if (!mounted) return;
          setState(() => _isFullyDownloaded = true);
        },
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: DetailsScreenHeaderDelegate(
                tickerProvider: this,
                gallery: widget.tour.gallery,
                title: widget.tour.name,
                action: action,
              ),
            ),
            if (!_isFullyDownloaded)
              const SliverToBoxAdapter(child: TourNotDownloadedWarning()),
            SliverToBoxAdapter(
                child: DetailsDescription(desc: widget.tour.desc)),
            const SliverToBoxAdapter(
              child: DetailsHeader(
                title: "Tour Stops",
              ),
            ),
            _WaypointList(tour: widget.tour),
            const SliverToBoxAdapter(child: SizedBox(height: 6)),
          ],
        ),
      ),
    );
  }
}

class TourNotDownloadedWarning extends StatelessWidget {
  const TourNotDownloadedWarning({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: 16.0,
      ),
      color: Theme.of(context).colorScheme.secondary.withAlpha(128),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Note",
            style: Theme.of(context)
                .textTheme
                .labelMedium!
                .copyWith(color: Colors.white.withAlpha(128)),
          ),
          const SizedBox(height: 6.0),
          Text(
            "You can view information about this tour before downloading it, but "
            "the tour must be fully downloaded before use.",
            style: Theme.of(context)
                .textTheme
                .bodyLarge!
                .copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton({
    super.key,
    required this.tour,
    required this.onDownloaded,
  });

  final TourModel tour;
  final void Function() onDownloaded;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  final ValueNotifier<double> _downloadProgress = ValueNotifier(0.0);
  MultiDownload? _tourDownload;

  @override
  void initState() {
    super.initState();

    (() async {
      var allDownloaded = true;
      var inProgress = true;
      var downloadsInProgress = <Download>[];
      for (final asset in widget.tour.allAssets) {
        var isDownloaded = await asset.isDownloaded;

        if (!isDownloaded) {
          allDownloaded = false;

          var downloadInProgress =
              DownloadManager.instance.downloadInProgress(asset.name);

          if (downloadInProgress == null) {
            inProgress = false;
          } else {
            downloadsInProgress.add(downloadInProgress);
          }
        }
      }

      if (allDownloaded) {
        widget.onDownloaded();
      } else if (inProgress) {
        var download = MultiDownload.of(downloadsInProgress);

        download.downloadProgress.listen((progress) {
          _downloadProgress.value =
              progress.downloadedSize / (progress.totalDownloadSize ?? 0);
        });

        download.completed.then((_) {
          widget.onDownloaded();
        }).onError((error, stackTrace) {
          if (kDebugMode) {
            print("Fatal error while downloading: $error");
            print("Stack trace: $stackTrace");
          }
        });

        setState(() {
          _tourDownload = download;
        });
      }
    })();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: const BorderRadius.all(Radius.circular(12.0)),
            ),
          ),
        ),
        Positioned.fill(
          child: ClipRect(
            clipper: _DownloadIconClipper(_downloadProgress),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: const BorderRadius.all(Radius.circular(12.0)),
              ),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _download,
          style: const ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.transparent),
            shadowColor: MaterialStatePropertyAll(Colors.transparent),
            foregroundColor: MaterialStatePropertyAll(Colors.white),
            padding: MaterialStatePropertyAll(EdgeInsets.zero),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12.0)),
              ),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            children: [
              const SizedBox(width: 12.0),
              const Icon(Icons.download),
              const SizedBox(width: 8.0),
              Text(_tourDownload != null ? "Downloading..." : "Download"),
              const SizedBox(width: 12.0),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _download() async {
    if (_tourDownload == null) {
      bool shouldDownload = await Navigator.push(
          context,
          DialogRoute(
              context: context, builder: (context) => _DownloadDialog()));

      if (!shouldDownload || !mounted) return;

      var download = DownloadManager.instance.downloadAll(
        widget.tour.allAssets,
        _CallbackSink((progress) {
          _downloadProgress.value = progress.downloadedSize.toDouble() /
              (progress.totalDownloadSize ?? 0).toDouble();
        }),
      );

      download.downloadProgress.listen((progress) {
        _downloadProgress.value =
            progress.downloadedSize / (progress.totalDownloadSize ?? 0);
      });

      download.completed.then((_) {
        widget.onDownloaded();
      }).onError((error, stackTrace) {
        if (kDebugMode) {
          print("Fatal error while downloading: $error");
          print("Stack trace: $stackTrace");
        }
      });

      setState(() {
        _tourDownload = download;
      });
    } else {}
  }
}

class _WaypointList extends StatelessWidget {
  const _WaypointList({
    Key? key,
    required this.tour,
  }) : super(key: key);

  final TourModel? tour;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        childCount: tour?.waypoints.length ?? 0,
        (context, index) {
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: WaypointCard(
              waypoint: tour!.waypoints[index],
              index: index,
            ),
          );
        },
      ),
    );
  }
}

class _DownloadIconClipper extends CustomClipper<Rect> {
  _DownloadIconClipper(this.reclip) : super(reclip: reclip) {
    reclip.addListener(_onClipChanged);
  }

  void dispose() {
    reclip.removeListener(_onClipChanged);
  }

  final ValueNotifier<double> reclip;

  late double currentClip = reclip.value;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * currentClip, size.height);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => true;

  void _onClipChanged() {
    currentClip = reclip.value;
  }
}

class _DownloadDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download Tour'),
      content: SingleChildScrollView(
        child: ListBody(
          children: const <Widget>[
            Text(
              'Downloading this tour may incur data charges. '
              'It is recommended to connect to WiFi before proceeding.',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('Download'),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}

class _CallbackSink<T> implements Sink<T> {
  const _CallbackSink(this.callback);

  final void Function(T) callback;

  @override
  void add(T data) {
    callback(data);
  }

  @override
  void close() {}
}
