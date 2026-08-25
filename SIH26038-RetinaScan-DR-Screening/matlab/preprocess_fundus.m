function out = preprocess_fundus(imgPath, outDir)
% PREPROCESS_FUNDUS  Module 1 of SIH26038 pipeline.
% Quality gate (focus / illumination / field-of-view) + enhancement
% (Ben-Graham crop, CLAHE, illumination flattening) + recapture feedback.
% Usage:  out = preprocess_fundus("fundus.jpg", "processed/")
%
% Image Processing Toolbox required.

    I = imread(imgPath);
    if size(I,3) == 1, I = repmat(I,[1 1 3]); end
    [H0, W0, ~] = size(I);

    S = struct(); S.file = imgPath; S.origSize = [H0 W0];

    %% ---- 1. FOV mask + Ben-Graham crop -------------------------------
    g = rgb2gray(I);
    mask = g > 12;                            % fundus field vs black border
    mask = imclose(mask, strel('disk', 15));
    mask = imfill(mask, 'holes');
    mask = bwareafilt(mask, 1);
    stats = regionprops(mask, 'BoundingBox', 'Area');
    if isempty(stats)
        error('No fundus field detected - not a fundus image?');
    end
    fovCoverage = stats.Area / (H0*W0);       % ~0.7+ on good images
    bb = round(stats.BoundingBox);
    Ic = imcrop(I, bb);
    maskc = imcrop(mask, bb);

    %% ---- 2. Quality gate ---------------------------------------------
    % Focus: variance of Laplacian inside mask
    gc = im2double(rgb2gray(Ic));
    lap = del2(gc);
    blurScore = std(lap(maskc)).^2 * 1e4;     % empirical scale
    % Illumination: mean brightness + uniformity inside mask
    lum = gc(maskc);
    meanLum = mean(lum);  lumStd = std(lum);

    reasons = strings(0);
    gradeable = true;
    if blurScore < 8,   reasons(end+1) = "image out of focus - hold camera steady, recapture"; gradeable = false; end
    if meanLum < 0.08,  reasons(end+1) = "too dark - increase illumination/dilate pupil, recapture"; gradeable = false; end
    if meanLum > 0.85,  reasons(end+1) = "overexposed - reduce flash intensity, recapture"; gradeable = false; end
    if fovCoverage < 0.45, reasons(end+1) = "incomplete field of view - recenter the eye, recapture"; gradeable = false; end

    S.quality.blurScore   = blurScore;
    S.quality.meanLum     = meanLum;
    S.quality.lumStd      = lumStd;
    S.quality.fovCoverage = fovCoverage;
    S.quality.gradeable   = gradeable;
    S.quality.feedback    = reasons;

    %% ---- 3. Enhancement (borderline/always) ---------------------------
    Ir = imresize(Ic, [512 512]);
    lab = rgb2lab(Ir);
    L = lab(:,:,1) / 100;
    L = adapthisteq(L, 'NumTiles', [8 8], 'ClipLimit', 0.01);   % CLAHE
    % illumination flattening: divide by large-scale gaussian estimate
    bg = imgaussfilt(L, 40, 'Padding','replicate');
    Ln = 0.5 * (L ./ max(bg,1e-3));
    Ln = min(max(rangesafe(Ln),0),1);
    lab(:,:,1) = Ln * 100;
    Ie = lab2rgb(lab);

    % vessel-friendly green channel variant (for segmentation stage)
    G = im2double(Ir(:,:,2));
    G = adapthisteq(G, 'NumTiles',[8 8]); 

    if nargin >= 2 && ~isempty(outDir)
        if ~exist(outDir,'dir'), mkdir(outDir); end
        [~, nm, ~] = fileparts(imgPath);
        imwrite(Ie, fullfile(outDir, nm + "_enh.png"));
        imwrite(G,  fullfile(outDir, nm + "_green.png"));
    end

    out = S;
    out.enhanced = Ie; out.greenChannel = G;
end

function x = rangesafe(x)  % local contrast fit to 2..98 percentile
    p2 = prctile(x(:),2); p98 = prctile(x(:),98);
    x = (x - p2) / max(p98 - p2, 1e-6);
end
