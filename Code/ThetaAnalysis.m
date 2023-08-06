function ThetaAna = ThetaAnalysis(Nav, Spk, Lfp, thetaparams)

%%
%Selecting time indices over which we'll look at spike-theta phase coupling
tidx = ismember(Nav.Condition, thetaparams.condition) &...
       ismember(Nav.XDir, thetaparams.dir) &...
       ismember(Nav.laptype, thetaparams.laptype) &...
       Nav.Spd >= thetaparams.spdthreshold &...
       ~isnan(Nav.Xpos);

   
cellidx = find(thetaparams.cellidx & sum(Spk.spikeTrain(tidx,:), 1) > thetaparams.nspk_th);
spikeTrain = Spk.spikeTrain(tidx,cellidx);

%number of cells selected for theta phase analysis
ncells = size(spikeTrain, 2);

%number of theta phase bins
nPhsbins = numel(thetaparams.Phsbinedges) - 1;

%%
%Statistics based on distribution of spike theta phase.

%Initializing arrays.
scmap = NaN(ncells, nPhsbins);%spike count array
rL = NaN(ncells,1);%Resultant length array
Rpval = NaN(ncells,1);%Rayleigh test p-value
phsmean = NaN(ncells,1);%Rayleigh test p-value

%Looping across cells to build phase-locking statistics
for icell = 1:ncells
    %Getting the phase at spike times by interpolation
    sph = interp1(Lfp.sampleTimes_raw, thetaphs_raw, Spk.spikeTimes(Spk.spikeID == cellidx(icell)), 'linear', NaN);

    %Removing NaNs just in case
    sph(isnan(sph)) = [];

    %Building histogram of spike phases.
    scmap(icell,:) = histcounts(sph, thetaparams.Phsbinedges);

    %Resultant vector length.
    rL(icell) = circ_r(sph / 180 * pi);
    phsmean(icell) = circ_mean(sph / 180 * pi) / pi * 180;
    Rpval(icell) = circ_rtest(sph / 180 * pi);

end
   
%%
% Another way to compute the modulation of spiking by theta phase is by 
% computing a map (i.e. spike count map / occupancy map).

% %Retrieving the default parameters to compute maps.
phsmapsparams = DefineMapsParams(Nav,Spk);

%Replacing values for time indices selection.
phsmapsparams.condition = thetaparams.condition;
phsmapsparams.dir = thetaparams.dir;
phsmapsparams.spdthreshold = thetaparams.spdthreshold;

%Name of the field in Nav to use as the independent variable
phsmapsparams.Xvariablename = 'ThetaPhase';

%Filling that field with the theta phase sampled at the right frequency
Nav.ThetaPhase = thetaphs;

%Replacing binning parameters.
phsmapsparams.Xrange = thetaparams.Phsrange;
phsmapsparams.Xbinsize = thetaparams.Phsbinsize;
phsmapsparams.Xsmthbinsize = thetaparams.Phssmthbinsize;
phsmapsparams.XsmthNbins = thetaparams.Phssmthbinsize / thetaparams.Phsbinsize;
phsmapsparams.Xbinedges = thetaparams.Phsrange(1):thetaparams.Phsbinsize:thetaparams.Phsrange(2);

%Now we can run MapsAnalysis with the new Nav and phsmapsparams.
Phsmaps = MapsAnalyses(Nav, Spk.spikeTrain, phsmapsparams);

%%
%First plotting position versus theta phase of spikes (after splitting
%according to the direction of travel...)
% figure;
% for icell = 1:ncells
% scatter(Nav.Xpos(tidx & Spk.spikeTrain(:,cellidx(icell))>0),Lfp.ThetaPhase(tidx & Spk.spikeTrain(:,cellidx(icell))>0),'.');
% pause
% end

%%
%Construct 2D maps of mean firing rate as a function of position and theta
%phase.

%number of position and theta phase bins
nPhsbins = numel(thetaparams.Phsbinedges) - 1;
nXbins = numel(thetaparams.Xbinedges) - 1;

%Discretizing theta phases
phs = Lfp.ThetaPhase(tidx);
phs_discrete = discretize(phs, thetaparams.Phsbinedges);

%Discretizing positions
Xpos = Nav.Xpos(tidx);
Xpos_discrete = discretize(Xpos, thetaparams.Xbinedges);

%Computing occupancy map
flat = 1/thetaparams.sampleRate * ones(size(Xpos_discrete));
occmap = Compute2DMap(phs_discrete, Xpos_discrete, flat, nPhsbins, nXbins);

%Removing occupancy for position x theta phase bins below the occupancy 
%threshold
occmap(occmap <= thetaparams.occ_th) = NaN;

%Smoothing the occupancy map with a 2D gaussian window.
occmap = repmat(occmap, [1 3]);
occmap = GaussianSmooth(occmap, [thetaparams.XsmthNbins thetaparams.PhssmthNbins]);
occmap = occmap(:,(nPhsbins+1):2*nPhsbins);

%Computing and smoothing the spike count map for each cell
scmap = NaN(ncells, nXbins, nPhsbins);
for icell = 1:ncells
    scmaptemp = Compute2DMap(phs_discrete, Xpos_discrete, spikeTrain(:,icell), nPhsbins, nXbins);
    scmaptemp(isnan(occmap)) = NaN;
    scmaptemp = repmat(scmaptemp, [1 3]);
    scmaptemp = GaussianSmooth(scmaptemp, [thetaparams.XsmthNbins thetaparams.PhssmthNbins]);
    scmap(icell,:,:) = scmaptemp(:, (nPhsbins+1):2*nPhsbins);
end

%Calculating the place field x theta phase maps by dividing scmap and 
%occmap
occmap = permute(occmap, [3 1 2]);%permuting dimension for convenience
mapXTheta = scmap ./ occmap;

%%

%Estimating the average decoding error as a function of the phase of the 
% theta oscillation

%Running the decoder (direction x position) with the default parameters
decparams = DefineDecParams(Nav, Spk);
Dec = DecodingAnalysis2D(Nav, Spk.spikeTrain, decparams);

%Calculating the decoding error 
XErrMax = (Dec.XDecMax - Dec.X) .* sign(Nav.XDir);

%Selecting time indices avoiding edges
minmax = [25 75];
tidxdec = tidx & Nav.Xpos > minmax(1) &  Nav.Xpos < minmax(2);
phs = Lfp.ThetaPhase(tidxdec);

%Discretizing theta phases
phs_discrete = discretize(phs, thetaparams.Phsbinedges);

%Computing and smoothing cicularly the sum of decoding errors across theta
%phases
summap = Compute1DMap(phs_discrete, XErrMax(tidx & Nav.Xpos > minmax(1) &  Nav.Xpos < minmax(2)), nPhsbins);
summap = GaussianSmooth(repmat(summap,[1 3]), [0 1]);
summap = summap((nPhsbins+1):2*nPhsbins);

%Computing the occupancy map
occmap = Compute1DMap(phs_discrete, ones(size(phs_discrete)), nPhsbins);
occmap = GaussianSmooth(repmat(occmap,[1 3]), [0 1]);
occmap = occmap((nPhsbins+1):2*nPhsbins);

%Calculating the average decoding error across theta phases
ThetaXDec = summap ./ occmap;

%%
ncells_orig = size(Srep, 2);

ThetaAna.rL = NaN(ncells_orig,1);
ThetaAna.phsmean = NaN(ncells_orig,1);
ThetaAna.Rpval = NaN(ncells_orig,1);

ThetaAna.rL(cellidx) = rL;
ThetaAna.phsmean(cellidx) = phsmean;
ThetaAna.Rpval(cellidx) = Rpval;

ThetaAna.Phsmaps = Phsmaps;
ThetaAna.mapXTheta = mapXTheta;
ThetaAna.ThetaXDec = ThetaXDec;




   %%
%Same thing as above but after centering position on the position of max
%firing rate and normalizing positions by the field width.

%number of position and theta phase bins
nPhsbins = numel(thetaparams.Phsbinedges) - 1;

%Discretizing theta phases
phs = Lfp.ThetaPhase(tidx);
phs_discrete = discretize(phs, thetaparams.Phsbinedges);

%position of max firing rate
mapX = Maps.mapX(cellidx,:);
[~, imaxPos] = max(mapX, [], 2);
maxPos = Maps.bincenters(imaxPos);

%Identifying limits of subfield edges.
ifieldstart = NaN(1, ncells);
ifieldend = NaN(1, ncells);
field_th = 0.10;%amplitude threshold to identify field limits
for icell = 1:ncells
    ma = max(mapX(icell,:));
    mi = min(mapX(icell,:));
    startidx = find(mapX(icell,1:imaxPos(icell)) <= mi + field_th * (ma - mi), 1, 'last');
    if isempty(startidx)
        startidx = 1;
    end
    ifieldstart(icell) = startidx;
    
    endidx = imaxPos(icell) + find(mapX(icell,(imaxPos(icell)+1):end) <= mi + field_th * (ma - mi), 1, 'first');
    if isempty(endidx)
        endidx = size(mapX, 2);
    end
    ifieldend(icell) = endidx;
end

fieldstart = Maps.bincenters(ifieldstart);
fieldend = Maps.bincenters(ifieldend);

%Computing linear-circular coefficients and position x theta phase maps for
%each cell after centering and nomralizing the position of the animal to
%within field limits.
Xbinedges_norm = -1:0.1:1;
nXbins_norm = numel(Xbinedges_norm) - 1;
XsmthNbins_norm = 2;
mapXTheta2 = NaN(ncells, nXbins_norm, nPhsbins);
ThetaRho = NaN(ncells, 1);
ThetaRho_pval = NaN(ncells, 1);
ThetaSlope = NaN(ncells, 1);
ThetaPhi0 = NaN(ncells, 1);
ThetaNspk = NaN(ncells, 1);
for icell = 1:ncells
    %Discretizing positions
    if numel(unique(Maps.mapsparams.dir)) > 1
        error('phase precession on linear track should be estimated from traversals in a single direction')
    end
    Xpos = (Nav.Xpos(tidx) - maxPos(icell)) * sign(Maps.mapsparams.dir);
    Xpos(Xpos < 0) = Xpos(Xpos < 0) / abs(maxPos(icell) - fieldstart(icell));
    Xpos(Xpos > 0) = Xpos(Xpos > 0) / abs(fieldend(icell) - maxPos(icell));
    Xpos(abs(Xpos) > 1) = NaN;
    Xpos_discrete = discretize(Xpos, Xbinedges_norm);
    
    %Estimating the linear-circular coefficient and its significance
    spkidx = spikeTrain(:,icell) > 0;
    [ThetaRho(icell) ,ThetaRho_pval(icell), ThetaSlope(icell) ,ThetaPhi0(icell)] = ...
        circlin_regression(Xpos(spkidx), phs(spkidx) /180 *pi);
    ThetaNspk(icell) = sum(spkidx);
    
    %Computing occupancy map
    flat = 1/thetaparams.sampleRate * ones(size(Xpos_discrete));
    occmap = Compute2DMap(phs_discrete, Xpos_discrete, flat, nPhsbins, nXbins_norm);
    
    %Removing occupancy for position x theta phase bins below the occupancy
    %threshold
    occmap(occmap <= thetaparams.occ_th) = NaN;
    
    %Smoothing the occupancy map with a 2D gaussian window.
    occmap = repmat(occmap, [1 3]);
    occmap = GaussianSmooth(occmap, [XsmthNbins_norm thetaparams.PhssmthNbins]);
    occmap = occmap(:,(nPhsbins+1):2*nPhsbins);
    
    %Computing and smoothing the spike count map for each cell
    
    scmap = Compute2DMap(phs_discrete, Xpos_discrete, spikeTrain(:,icell), nPhsbins, nXbins_norm);
    scmap(isnan(occmap)) = NaN;
    scmap = repmat(scmap, [1 3]);
    scmap = GaussianSmooth(scmap, [thetaparams.XsmthNbins thetaparams.PhssmthNbins]);
    scmap = scmap(:, (nPhsbins+1):2*nPhsbins);
    
    mapXTheta2(icell,:,:) = scmap ./ occmap;
end


%%
%Decoding positions around ripple times

%Detecting ripple peaks
ripFs = 1 / mean(diff(Lfp.sampleTimes));
riptimes = find(Lfp.ripplepeak == 1);


%Extracting snippets of Decoded positions around ripple peaks.
idxwin = -round(0.1 * ripFs):round(0.1 * ripFs);
[~, ~, lrip] = ComputeTriggeredAverage(Dec.XDecMax, riptimes, idxwin);

end