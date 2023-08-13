function Dec = DecodingAnalysis(Nav, Srep, decparams)
% Dec = DecodingAnalysis(Nav, Srep, decparams)
% Decoding up to two behavioral variables from a set of neuron's spike 
% trains using 2D spatial maps.
%
%
% Inputs:
%   Nav: Structure containing dependent variables (X and Y).
%   Srep: Spike train data for each neuron (timepoints x neurons).
%   decparams: Structure with decoding parameters. See DefineDecParams.
%
% Outputs:
%   Dec: Structure containing decoding results, with the following fields:
%   - traintidx: Logical indices of data points used for training.
%   - Xbincenters: Centers of the X bins.
%   - nXbins: Number of X bins.
%   - Ybincenters: Centers of the Y bins.
%   - nYbins: Number of Y bins.
%   - mapXY: Place field maps for each cell (ncells x nXbins x nYbins).
%   - mapXY_cv: Cross-validated place field maps (ncells x nXbins x nYbins x k-fold).
%   - occmap: Occupancy map used for decoding.
%   - X: Discretized X values.
%   - Y: Discretized Y values.
%   - XDecMax: Decoded X using the maximum a posteriori.
%   - YDecMax: Decoded Y using the maximum a posteriori.
%   - XDecMean: Decoded X using the expectancy of the posterior.
%   - YDecMean: Decoded Y using the expectancy of the posterior.
%   - XErrMax: Decoding error for X using maximum a posteriori.
%   - YErrMax: Decoding error for Y using maximum likelihood.
%   - XErrMean: Decoding error for X using the expectancy of the posterior.
%   - YErrMean: Decoding error for Y using the expectancy of the posterior.
%   - Xdecmat: Confusion matrix for X over the training set.
%   - Ydecmat: Confusion matrix for Y over training set variables.
%
%
% Usage:
%   Dec = DecodingAnalysis(Nav, Srep, decparams)
%
% See Also:
%   ComputeBayesMAP, crossvalPartition, GaussianSmooth, ComputeMap
%
% Written by J. Fournier in 08/2023 for the iBio Summer school.
%%

if isempty(decparams.Xvariablename)
    decparams.Xvariablename = 'X';
end
X = Nav.(decparams.Xvariablename);

%If no Y variable are indicated, we'll just compute a 1D place field
if ~isempty(decparams.Yvariablename)
    Y = Nav.(decparams.Yvariablename);
else
    Y = ones(size(X));
    decparams.Ybinedges = 1;
    decparams.YsmthNbins = 0;
end

%Smoothing the spike train over the decoding window to get spike counts
spkCount = zeros(size(Srep));
decbinwin = 2 * floor(0.5 * decparams.dectimewin * decparams.sampleRate) + 1;
for icell = 1:size(Srep,2)
    spkCount(:,icell) = smooth(Srep(:,icell), decbinwin) * decbinwin;
end

%Time indices over which place fields used for decoding will be estimated.
traintidx = ismember(Nav.Condition, decparams.condition) &...
            ismember(Nav.XDir, decparams.dir) &...
            Nav.Spd > decparams.spdthreshold &...
            X >= decparams.Xbinedges(1) & X <= decparams.Xbinedges(end) &...
            Y >= decparams.Ybinedges(1) & Y <= decparams.Ybinedges(end) &...
            ~isnan(X) & ~isnan(Y);

%Selecting cell indices over which to compute place fields
if islogical(decparams.cellidx)
    cellidx = find(decparams.cellidx(:)' & sum(Srep(traintidx,:), 1, 'omitnan') > decparams.nspk_th);
else
    cellidx = decparams.cellidx(sum(Srep(traintidx,decparams.cellidx), 1, 'omitnan') > decparams.nspk_th);
end

%Subsetting spike trains across cells.
spikeTrain = Srep(:,cellidx);
spkCount = spkCount(:,cellidx);

%number of cells selected for decoding
ncells = size(spikeTrain, 2);

%number of X bins
nXbins = max(1, numel(decparams.Xbinedges) - 1);

%number of Y bins
nYbins = max(1, numel(decparams.Ybinedges) - 1);

%%
%Discretizing X according to decparams.Xbinedges
X_discrete = discretize(X, decparams.Xbinedges);

%Discretizing Y according to decparams.Ybinedges.
Y_discrete = discretize(Y, decparams.Ybinedges);

%%
%Subsetting X_discrete, Y_discrete and spikeTrain on the training set
X_discrete_trainset = X_discrete(traintidx);
Y_discrete_trainset = Y_discrete(traintidx);
spkTrain_trainset = spikeTrain(traintidx,:);

%Computing occupancy map (same for all cells) on the train set
flat = decparams.scalingFactor * ones(size(X_discrete_trainset));
occmap = ComputeMap(X_discrete_trainset, Y_discrete_trainset, flat, nXbins, nYbins);

%Removing occupancy for position bins below the occupancy threshold
occmap(occmap <= decparams.occ_th) = NaN;

%Smoothing the occupancy map with a 2D gaussian window.
occmap = GaussianSmooth(occmap, [decparams.YsmthNbins decparams.XsmthNbins]);

%Computing and smoothing the spike count map for each cell
scmap = NaN(ncells, nYbins, nXbins);
for icell = 1:ncells
    scmapcell = ComputeMap(X_discrete_trainset, Y_discrete_trainset, spkTrain_trainset(:,icell), nXbins, nYbins);
    scmapcell(isnan(occmap)) = NaN;
    scmapcell = GaussianSmooth(scmapcell, [decparams.YsmthNbins decparams.XsmthNbins]);
    scmap(icell,:,:) = scmapcell;
end

%Calculating the place field x direction maps by dividing scmap and occmap
mapXY = scmap ./ permute(occmap, [3 1 2]);

%%
%number of data points
ntimepts = size(spkCount, 1);

%Initializing decoded variables
XDecMax = NaN(ntimepts,1);
YDecMax = NaN(ntimepts,1);
XDecMean = NaN(ntimepts,1);
YDecMean = NaN(ntimepts,1);
%Computing decoded positions for data points that are not included in the
%train set.
[XDecMax(~traintidx), YDecMax(~traintidx), XDecMean(~traintidx), YDecMean(~traintidx)] = ...
    ComputeBayesMAP(mapXY, spkCount(~traintidx,:), decparams.dectimewin);

%%
%Doing the same thing now with cross-validated data on the train set.
%First defining a partition of the data for k-fold cross-validation. NB: we
%should normally be more careful about the fact that the spike count data
%are actually smoothed over time...
ntimepts_trainset = sum(traintidx);
cv = crossvalPartition(ntimepts_trainset, decparams.kfold);

%Computing the place field using k-fold cross-validation
mapXY_cv = NaN(ncells, nYbins, nXbins, decparams.kfold);
XDecMax_cv = NaN(ntimepts_trainset,1);
YDecMax_cv = NaN(ntimepts_trainset,1);
XDecMean_cv = NaN(ntimepts_trainset,1);
YDecMean_cv = NaN(ntimepts_trainset,1);
X_discrete_trainset = X_discrete(traintidx);
Y_discrete_trainset = Y_discrete(traintidx);
spkTrain_trainset = spikeTrain(traintidx,:);
spkCount_trainset = spkCount(traintidx,:);
for i = 1:decparams.kfold
    %Subsetting X and spiketrain according to the train set of the
    %current fold
    Xtraining = X_discrete_trainset(cv.trainsets{i});
    Ytraining = Y_discrete_trainset(cv.trainsets{i});
    Spktraining = spkTrain_trainset(cv.trainsets{i},:);
    
    %Computing occupancy map for the current fold
    flat = decparams.scalingFactor * ones(size(Xtraining));
    occmap_cv = ComputeMap(Xtraining, Ytraining, flat, nXbins, nYbins);
    occmap_cv(occmap_cv <= decparams.occ_th) = NaN;
    occmap_cv = GaussianSmooth(occmap_cv, [decparams.YsmthNbins decparams.XsmthNbins]);
    
    %Computing the spike count map and place field of each cell for the
    %current fold
    for icell = 1:ncells
        scmap_cv = ComputeMap(Xtraining, Ytraining, Spktraining(:,icell), nXbins, nYbins);
        scmap_cv(isnan(occmap_cv)) = NaN;
        scmap_cv = GaussianSmooth(scmap_cv, [decparams.YsmthNbins decparams.XsmthNbins]);
        mapXY_cv(icell,:,:,i) = scmap_cv ./ occmap_cv;
    end
end

%Now that we've got cross-validated place fields for the train set, we can
%compute decoded positions on the train set using the same k-fold
%partition.
for i = 1:decparams.kfold
    spkCountTest = spkCount_trainset(cv.testsets{i},:);
    
    [XDecMax_cv(cv.testsets{i}), YDecMax_cv(cv.testsets{i}),...
     XDecMean_cv(cv.testsets{i}), YDecMean_cv(cv.testsets{i})] = ComputeBayesMAP(mapXY_cv(:,:,:,i), spkCountTest, decparams.dectimewin);
end

%Filling in cross-validated decoded positions for the train set.
XDecMax(traintidx) = XDecMax_cv;
YDecMax(traintidx) = YDecMax_cv;
XDecMean(traintidx) = XDecMean_cv;
YDecMean(traintidx) = YDecMean_cv;

%%
%Populate the output structure with results to be saved
decparams.traintidx = traintidx;
Dec.decparams = decparams;

ncells_orig = size(Srep, 2);
Dec.Xbincenters = decparams.Xbinedges(1:end-1) + decparams.Xbinsize / 2;
Dec.nXbins = nXbins;

Dec.nYbins = nYbins;
if nYbins > 1
    Dec.Ybincenters = decparams.Ybinedges(1:end-1) + decparams.Ybinsize / 2;
else
    Dec.Ybincenters = 1;
end

Dec.mapXY = NaN(ncells_orig, nYbins, nXbins);
Dec.mapXY_cv = NaN(ncells_orig, nYbins, nXbins, decparams.kfold);
Dec.occmap = NaN(1, nYbins, nXbins);

Dec.mapXY(cellidx,:,:) = mapXY;
Dec.mapXY_cv(cellidx,:,:,:) = mapXY_cv;
Dec.occmap = occmap;

Dec.X = X_discrete;
Dec.Y = Y_discrete;

Dec.XDecMax = XDecMax;
Dec.YDecMax = YDecMax;
Dec.XDecMean = XDecMean;
Dec.YDecMean = YDecMean;

Dec.XErrMax = (XDecMax - X_discrete);
Dec.YErrMax = YDecMax - Y_discrete;
Dec.XErrMean = (XDecMean - X_discrete);
Dec.YErrMean = YDecMean - Y_discrete;

%Calculating the distribution of decoded variables as a function of the 
%actual variables over the training set (just to be able to quickly check 
%the quality of decoding on that portion of the data).
Dec.Xdecmat = ComputeMap(Dec.X(traintidx), Dec.XDecMax(traintidx), ones(size(Dec.X(traintidx))), Dec.nXbins, Dec.nXbins);
Dec.Xdecmat = Dec.Xdecmat ./ sum(Dec.Xdecmat, 1, 'omitnan');
Dec.Ydecmat = ComputeMap(Dec.Y(traintidx), Dec.YDecMax(traintidx), ones(size(Dec.Y(traintidx))), Dec.nYbins, Dec.nYbins);
Dec.Ydecmat = Dec.Ydecmat ./ sum(Dec.Ydecmat, 1, 'omitnan');
end