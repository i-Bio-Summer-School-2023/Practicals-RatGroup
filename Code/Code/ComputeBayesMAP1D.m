function [DecMax, DecMean] = ComputeBayesMAP(map, spkCount, dectimewin, mapprior)
%Computes the decoded position as the maximum or the mean of the posterior
%probability distribution. The posterior probabilities are computed using a
%Bayesian approach, assuming independence between spike trains across
%cells. Map corresponds to the tuning curve model of size ncells x nbins
%expressed in spikes/second; spkCount, to the spike count across time for 
%all cells (ntimes x ncells); dectimewin, to the decoding window in
%seconds; mapprior (optional) is the prior distribution of the decoded
%variable. By default we assume a flat prior when mapprior is not provided.

if nargin < 4
    %if mapprior is not provided, we'll use a flat prior. Units don't
    %matter as this will be normalized later
    mapprior = ones(1, size(map, 2));
end

%Permuting dimensions to get first dimension as a singleton and do the 
%element-wise multiplication with spkCount more conveniently
map = permute(map, [3 1 2]);
mapprior = permute(mapprior, [3 1 2]);

%Computing the posterior probability P(X | spkcount). We'll do it as a for
%loop over the number of cells to avoid memory issues.
ncells = size(spkCount, 2);
map = map + eps;%to avoid reaching precision limit
Posterior = mapprior .* exp(-dectimewin .* sum(map, 2));
for icell = 1:ncells
    Posterior = Posterior .* map(1,icell,:) .^ spkCount(:,icell);
end

%We should end up with a matrix of probability of size Ntimes x Nbins
Posterior = squeeze(Posterior);

%Normalizing so to that the sum of probabilities over positions equals 1.
Posterior = Posterior ./ nansum(Posterior, 2);

%Taking the decoded position as the maximum of the posterior probability
%distribution (M.A.P. estimate)
[~, DecMax] = max(Posterior, [], 2);

%Taking the decoded position as the expected value of the position given 
%its posterior probability distribution
posbins = (1:size(Posterior, 2))';
Posterior(isnan(Posterior)) = 0;
DecMean = (Posterior * posbins) ./ sum(Posterior, 2);

%Ignoring decoded positions if no cell fired (optional)
mua = sum(spkCount, 2);
DecMax(mua == 0) = NaN;
DecMean(mua == 0) = NaN;
end