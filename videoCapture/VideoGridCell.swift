//
//  VideoGridCell.swift
//  videoCapture
//
//  Created by Aviram Netanel on 14/08/2025.
//

import UIKit

final class VideoGridCell: UICollectionViewCell {
  
  static var reuseIdentifier: String = "VideoGridCell"
  
    // Helps avoid wrong thumbnails on reuse
    var representedAssetIdentifier: String?

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 25
        return iv
    }()

    private let durationLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        l.layer.cornerRadius = 6
        l.clipsToBounds = true
        l.textAlignment = .center
        l.insetsLayoutMarginsFromSafeArea = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(durationLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            durationLabel.heightAnchor.constraint(equalToConstant: 22),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    } // init

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedAssetIdentifier = nil
        imageView.image = nil
        durationLabel.text = nil
    } // prepareForReuse

    func configure(image: UIImage?,
                   durationText: String,
                   assetIdentifier: String) {
        representedAssetIdentifier = assetIdentifier
        imageView.image = image
        durationLabel.text = "  \(durationText)  "
    } // configure
} // VideoGridCell
